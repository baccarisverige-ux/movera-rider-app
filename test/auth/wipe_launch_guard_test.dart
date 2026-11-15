import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Rules audits/impact/rider-wipe-partway.md, Round 2 (supervisor SF-1):
/// the new rider's tokens are saved before the wipe of the previous rider's
/// data. An app killed in that wipe starts again with the new rider's
/// session next to what is left; the start compares the stored session
/// with the owner record.

const _cards = 'movera_saved_cards';

String _token(String rider) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': rider})))
      .replaceAll('=', '');
  return 'h.$payload.s';
}

class _RemoveFails extends InMemorySharedPreferencesStore {
  _RemoveFails(super.data) : super.withData();

  String? failing;

  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.$failing') throw StateError('remove failed: $key');
    return super.remove(key);
  }
}

/// Rider A is recorded and A's cards are saved; the stored session is
/// [session]'s (null: no `sub` in the token).
Future<(_RemoveFails, MemoryTokenStore)> _killedIn({String? session}) async {
  SharedPreferences.setMockInitialValues({});
  final store = _RemoveFails(<String, Object>{
    'flutter.$_cards': '[{"id":"c1","last4":"4242"}]',
    'flutter.movera_onboarding_done': true,
  });
  final original = SharedPreferencesStorePlatform.instance;
  SharedPreferencesStorePlatform.instance = store;
  addTearDown(() => SharedPreferencesStorePlatform.instance = original);
  await (await SharedPreferences.getInstance()).reload();
  await UserDataWipe.enterSessionAs('sub:rider-a');
  final tokens = MemoryTokenStore();
  await tokens.save(
    access: session == null ? 'opaque-token' : _token(session),
    refresh: 'refresh',
  );
  return (store, tokens);
}

Future<SharedPreferences> _prefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    RideSnapshotStore.epoch = 0;
  });

  test('start with another rider\'s session: the previous rider\'s data is '
      'wiped, then the session\'s rider is recorded', () async {
    final (_, tokens) = await _killedIn(session: 'rider-b');
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);

    await UserDataWipe.guardStoredSession(tokens);

    final prefs = await _prefs();
    expect(prefs.getString(_cards), isNull);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNotNull);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
    expect(await tokens.readAccess(), isNotNull, reason: 'rider B stays in');
    expect(prefs.getBool('movera_onboarding_done'), isTrue);
  });

  test('start with another rider\'s session and a wipe that cannot finish: '
      'the session is cleared, the previous rider stays recorded', () async {
    final (store, tokens) = await _killedIn(session: 'rider-b');
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);

    store.failing = _cards;
    await UserDataWipe.guardStoredSession(tokens);

    final prefs = await _prefs();
    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
    expect(prefs.getString(_cards), isNotNull, reason: 'precondition');
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);
  });

  test(
    'start with the recorded rider\'s own session: nothing is touched',
    () async {
      final (_, tokens) = await _killedIn(session: 'rider-a');
      final ownerA = (await _prefs()).getString(
        UserDataWipe.riderFingerprintKey,
      );

      await UserDataWipe.guardStoredSession(tokens);

      final prefs = await _prefs();
      expect(prefs.getString(_cards), contains('4242'));
      expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);
      expect(await tokens.readAccess(), isNotNull);
    },
  );

  test('start with a session that names no rider (no sub), or with no '
      'session, or with nobody recorded: nothing is touched', () async {
    final (_, tokens) = await _killedIn();
    await UserDataWipe.guardStoredSession(tokens);
    expect((await _prefs()).getString(_cards), contains('4242'));
    expect(await tokens.readAccess(), isNotNull);

    await UserDataWipe.guardStoredSession(MemoryTokenStore());
    expect((await _prefs()).getString(_cards), contains('4242'));

    final prefs = await _prefs();
    await prefs.remove(UserDataWipe.riderFingerprintKey);
    final other = MemoryTokenStore();
    await other.save(access: _token('rider-b'), refresh: 'r');
    await UserDataWipe.guardStoredSession(other);
    expect((await _prefs()).getString(_cards), contains('4242'));
    expect(
      (await _prefs()).getString(UserDataWipe.riderFingerprintKey),
      isNull,
    );
    expect(await other.readAccess(), isNotNull);
  });

  test('a new rider killed in the wipe of their first sign-in is still '
      'asked for a name after the start finishes the wipe', () async {
    final (_, tokens) = await _killedIn(session: 'rider-b');
    // What the sign-in wrote before the wipe began.
    await UserDataWipe.noteNameOwed('sub:rider-b');

    await UserDataWipe.guardStoredSession(tokens);

    expect(await PendingRiderName.read(), isNotNull);
  });
}
