import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FLOW-1 / ARCH-15: the end of a session leaves nothing of the rider
/// behind, a lost session keeps it for the same rider, and a different
/// rider signing in on the device never sees the previous rider's data.
///
/// Port of the audit repro "signOut leaves per-user prefs behind", inverted.

const _deviceKeys = <String, Object>{
  'movera_onboarding_done': true,
  'movera_ride_catalog_v1': '{"categories":[]}',
  'movera_app_language': 'fr',
};

/// Every per-user key the app writes today.
const _riderA = <String, Object>{
  'movera_home_address': 'Rider A home',
  'movera_work_address': 'Rider A work',
  'movera_saved_places': '[{"title":"Gym","type":"gym","address":"x"}]',
  'movera_recent_addresses': <String>['Sveavagen 1'],
  'movera_previous_pickups_v1': '[]',
  'movera_on_demand_ride_history_v1': '[]',
  'movera_saved_cards':
      '[{"id":"c1","brand":"visa","last4":"4242","expMonth":12,"expYear":2030,"holder":"Rider A"}]',
  'movera_default_payment': 'card:c1',
  'movera_payment_methods': '[]',
  'movera_payment_business': false,
  'movera_wallet_first': false,
  'movera_profile_v1': '{"name":"Rider A"}',
  'movera_wallet_balance': 150.0,
  'movera_wallet_charged_rides': <String>['ride-a'],
  'movera_reservations_v1': '[]',
  'movera_safety_cache_v1': '{}',
  'movera_active_ride': '{}',
  'movera_pending_cancels': <String>[],
  'movera_voucher_code': 'A-VOUCHER',
  'movera.location.last_good_fix.v1':
      '{"lat":59.33,"lng":18.06,"savedAt":"2026-10-01T10:00:00Z"}',
};

Future<List<String>> _riderKeysLeft() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs
      .getKeys()
      .where((key) => key.startsWith('movera'))
      .where((key) => !_deviceKeys.containsKey(key))
      .toList()
    ..sort();
}

Future<void> _signInAs(String phone) async {
  final auth = AppScope.instance.auth;
  final challenge = await auth.requestOtp(phone: phone);
  await auth.verifyOtp(challenge: challenge, code: '1234');
}

/// The composed app's forced sign-out: a 401 whose refresh is rejected.
var _expiries = 0;

Future<void> _expireSession() async {
  // A fresh access token each time: the client expires a given token once.
  _expiries += 1;
  await AppScope.instance.tokens.save(
    access: 'flow1-expired-access-$_expiries',
    refresh: 'flow1-rejected-refresh',
  );
  await expectLater(
    AppScope.instance.api.post(
      '/api/v1/auth/refresh',
      body: {'refreshToken': 'flow1-rejected-refresh'},
    ),
    throwsA(isA<ApiError>()),
  );
  expect(await AppScope.instance.tokens.readAccess(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'movera_ride_pin': '4821',
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      ..._deviceKeys,
      ..._riderA,
    });
    RideSnapshotStore.epoch = 0;
    await AppScope.instance.tokens.clear();
  });

  test('sign-out removes every per-user store and keeps device keys', () async {
    final scope = AppScope.instance;
    await scope.tokens.save(access: 'a', refresh: 'b');
    // In-memory state of rider A.
    await scope.profile.update(
      RiderProfileData.defaults().copyWith(name: 'Rider A'),
    );
    await scope.savedPlaces.hydrate();
    await scope.savedCards.load();
    expect(scope.savedPlaces.shortcuts(), isNotEmpty, reason: 'precondition');
    expect(scope.savedCards.list(), isNotEmpty, reason: 'precondition');
    scope.wallet.add(
      WalletEntry(
        id: 'w1',
        kind: WalletEntryKind.credit,
        amountMinor: 15000,
        at: DateTime(2026),
      ),
    );
    NotificationsRepository.shared.ingest(
      const PushPayload(type: 'info', title: 'Hi Rider A', messageId: 'n1'),
      read: false,
    );
    MessagesRepository.forRide(
      'ride-a',
    ).add(const ChatMessage(text: 'At the door', fromRider: true));
    scope.ride.rideId = 'ride-a';

    await scope.auth.signOut();

    expect(await _riderKeysLeft(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    for (final key in _deviceKeys.keys) {
      expect(prefs.containsKey(key), isTrue, reason: '$key is device level');
    }
    expect(
      await const FlutterSecureStorage().readAll(),
      isEmpty,
      reason: 'tokens and ride PIN',
    );
    expect(await scope.auth.hasSession(), isFalse);

    expect(scope.profile.profile.name, isEmpty);
    expect(scope.savedPlaces.shortcuts(), isEmpty);
    expect(scope.savedCards.list(), isEmpty);
    expect(scope.wallet.entries, isEmpty);
    expect(scope.reservations.all, isEmpty);
    expect(scope.accountSecurity.state, isNull);
    expect(scope.promotion.value, isNull);
    expect(NotificationsRepository.shared.all(), isEmpty);
    expect(MessagesRepository.forRide('ride-a').messages, isEmpty);
    expect(scope.ride.rideId, isNull);
  });

  test('session expiry keeps the rider data for the same rider', () async {
    await _expireSession();

    final left = await _riderKeysLeft();
    // Only the last GPS position goes on expiry; everything else waits for
    // the rider to sign back in.
    expect(left, isNot(contains('movera.location.last_good_fix.v1')));
    for (final key in _riderA.keys.where((k) => k.startsWith('movera_'))) {
      expect(left, contains(key), reason: key);
    }
  });

  test('the same rider signing back in after expiry keeps the data', () async {
    await _signInAs('+46701234567');
    await _expireSession();
    await _signInAs('+46701234567');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('movera_home_address'), 'Rider A home');
    expect(prefs.getString('movera_profile_v1'), contains('Rider A'));
    expect(prefs.getDouble('movera_wallet_balance'), 150.0);
    expect(await AppScope.instance.auth.hasSession(), isTrue);
  });

  test(
    'a different rider signing in after expiry gets a wiped device',
    () async {
      await _signInAs('+46701234567');
      await _expireSession();
      await AppScope.instance.profile.update(
        RiderProfileData.defaults().copyWith(name: 'Rider A'),
      );

      await _signInAs('+46709876543');

      final left = await _riderKeysLeft();
      // rider-r5-31: and that the new rider still owes a name;
      // rider-r5-44: and since when they are signed in on this device.
      expect(left, [
        'movera_rider_fingerprint',
        'movera_rider_name_pending',
        'movera_rider_session_started_at',
      ], reason: 'only who is signed in');
      expect(AppScope.instance.profile.profile.name, isEmpty);
      expect(
        await AppScope.instance.auth.hasSession(),
        isTrue,
        reason: 'the new rider stays signed in',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'movera_rider_fingerprint',
        ),
        isNot(contains('4670')),
        reason: 'the phone number is not stored in plain prefs',
      );
    },
  );
}
