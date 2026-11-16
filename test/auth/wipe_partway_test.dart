import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Rules audits/impact/rider-wipe-partway.md: a wipe that stops part-way
/// (one key cannot be removed) keeps the previous rider recorded, so the
/// next rider's sign-in runs the wipe again and never opens the app next
/// to the previous rider's data.

const _riderA = '+46701234567';
const _riderB = '+46701740650';
const _cards = 'movera_saved_cards';

/// What rider A left on the device.
const _dataA = <String, Object>{
  'flutter.movera_onboarding_done': true,
  'flutter.movera_app_language': 'fr',
  'flutter.movera_home_address': 'Rider A home',
  'flutter.$_cards':
      '[{"id":"c1","brand":"visa","last4":"4242","expMonth":12,"expYear":2030,"holder":"Rider A"}]',
  'flutter.movera_profile_v1': '{"name":"Rider A"}',
  'flutter.movera_wallet_balance': 150.0,
  'flutter.movera.location.last_good_fix.v1':
      '{"lat":59.33,"lng":18.06,"savedAt":"2026-10-01T10:00:00Z"}',
};

/// A store that cannot remove [failing]: it throws, or with [refuses]
/// answers false (the platform's "not removed").
class _RemoveFails extends InMemorySharedPreferencesStore {
  _RemoveFails(super.data) : super.withData();

  String? failing;
  bool refuses = false;
  void Function(String key)? onRemove;

  @override
  Future<bool> remove(String key) async {
    onRemove?.call(key);
    if (key == 'flutter.$failing') {
      if (refuses) return false;
      throw StateError('remove failed: $key');
    }
    return super.remove(key);
  }
}

Future<_RemoveFails> _deviceOfRiderA() async {
  SharedPreferences.setMockInitialValues({});
  final store = _RemoveFails(Map<String, Object>.of(_dataA));
  final original = SharedPreferencesStorePlatform.instance;
  SharedPreferencesStorePlatform.instance = store;
  addTearDown(() => SharedPreferencesStorePlatform.instance = original);
  await (await SharedPreferences.getInstance()).reload();
  return store;
}

Future<SharedPreferences> _prefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}

Future<void> _signInAs(String phone) async {
  final auth = AppScope.instance.auth;
  final challenge = await auth.requestOtp(phone: phone);
  await auth.verifyOtp(challenge: challenge, code: '1234');
}

var _expiries = 0;

/// The composed app's forced sign-out: a 401 whose refresh is rejected.
Future<void> _expireSession() async {
  _expiries += 1;
  await AppScope.instance.tokens.save(
    access: 'partway-expired-access-$_expiries',
    refresh: 'partway-rejected-refresh',
  );
  await expectLater(
    AppScope.instance.api.post(
      '/api/v1/auth/refresh',
      body: {'refreshToken': 'partway-rejected-refresh'},
    ),
    throwsA(isA<ApiError>()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    RideSnapshotStore.epoch = 0;
  });

  test('a wipe that stops part-way does not record the next rider, and '
      'their next sign-in wipes again', () async {
    final store = await _deviceOfRiderA();
    await UserDataWipe.enterSessionAs('phone:$_riderA');
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);
    expect(ownerA, isNotNull);

    store.failing = _cards;
    try {
      await UserDataWipe.enterSessionAs('phone:$_riderB');
    } catch (_) {
      // The sign-in is refused (the fix); before it, it went through.
    }
    var prefs = await _prefs();
    expect(prefs.getString(_cards), isNotNull, reason: 'precondition');
    expect(
      prefs.getString(UserDataWipe.riderFingerprintKey),
      ownerA,
      reason: 'rider A is still the one whose data is on the device',
    );

    store.failing = null;
    expect(await UserDataWipe.enterSessionAs('phone:$_riderB'), isTrue);
    prefs = await _prefs();
    expect(prefs.getString(_cards), isNull);
    expect(prefs.getString('movera_home_address'), isNull);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNotNull);
  });

  test('real app: rider B is never signed in next to rider A\'s data '
      '(the wipe stops part-way, then B signs in again)', () async {
    final store = await _deviceOfRiderA();
    final scope = AppScope.instance;
    await scope.tokens.clear();
    await _signInAs(_riderA);
    await _expireSession();
    await scope.profile.update(
      RiderProfileData.defaults().copyWith(name: 'Rider A'),
    );
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);

    store.failing = _cards;
    Object? refused;
    try {
      await _signInAs(_riderB);
    } catch (error) {
      refused = error;
    }
    var prefs = await _prefs();
    expect(prefs.getString(_cards), isNotNull, reason: 'precondition');
    expect(
      await scope.auth.hasSession(),
      isFalse,
      reason: 'rider B must not be signed in while rider A\'s cards are here',
    );
    expect(refused, isNotNull, reason: 'the sign-in fails, it is not silent');
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);

    store.failing = null;
    await _signInAs(_riderB);
    prefs = await _prefs();
    expect(await scope.auth.hasSession(), isTrue);
    expect(prefs.getString(_cards), isNull);
    expect(prefs.getString('movera_home_address'), isNull);
    expect(prefs.getDouble('movera_wallet_balance'), isNull);
    expect(prefs.getString('movera.location.last_good_fix.v1'), isNull);
    expect(scope.profile.profile.name, isEmpty);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
    expect(prefs.getBool('movera_onboarding_done'), isTrue);
    expect(prefs.getString('movera_app_language'), 'fr');
  });

  test('a sign-out wipe that stops part-way (remove answers false) keeps '
      'rider A recorded, so rider B\'s sign-in wipes the rest', () async {
    final store = await _deviceOfRiderA();
    final scope = AppScope.instance;
    await scope.tokens.clear();
    await _signInAs(_riderA);
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);

    store
      ..failing = _cards
      ..refuses = true;
    await scope.auth.signOut();
    var prefs = await _prefs();
    expect(await scope.auth.hasSession(), isFalse, reason: 'signed out');
    expect(prefs.getString(_cards), isNotNull, reason: 'precondition');
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);

    store.failing = null;
    await _signInAs(_riderB);
    prefs = await _prefs();
    expect(await scope.auth.hasSession(), isTrue);
    expect(prefs.getString(_cards), isNull);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
  });

  test('a full wipe removes the owner record, and removes it last', () async {
    final store = await _deviceOfRiderA();
    await UserDataWipe.enterSessionAs('phone:$_riderA');
    final removed = <String>[];
    store.onRemove = removed.add;

    await UserDataWipe.run();

    final prefs = await _prefs();
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNull);
    expect(removed.last, 'flutter.${UserDataWipe.riderFingerprintKey}');
    expect(removed, contains('flutter.$_cards'));
  });

  test('the same rider signing back in after a part-way wipe keeps what '
      'is left', () async {
    final store = await _deviceOfRiderA();
    final scope = AppScope.instance;
    await scope.tokens.clear();
    await _signInAs(_riderA);
    await _expireSession();
    store.failing = _cards;
    try {
      await _signInAs(_riderB);
    } catch (_) {}

    store.failing = null;
    await _signInAs(_riderA);
    final prefs = await _prefs();
    expect(await scope.auth.hasSession(), isTrue);
    expect(prefs.getString(_cards), contains('4242'));
  });

  test('the same rider signing back in after expiry keeps everything '
      '(no wipe)', () async {
    await _deviceOfRiderA();
    final scope = AppScope.instance;
    await scope.tokens.clear();
    await _signInAs(_riderA);
    await _expireSession();
    await _signInAs(_riderA);
    final prefs = await _prefs();
    expect(prefs.getString(_cards), contains('4242'));
    expect(prefs.getString('movera_home_address'), 'Rider A home');
    expect(prefs.getString('movera_profile_v1'), contains('Rider A'));
    expect(prefs.getDouble('movera_wallet_balance'), 150.0);
  });
}
