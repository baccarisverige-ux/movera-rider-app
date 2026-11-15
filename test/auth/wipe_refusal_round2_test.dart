import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/data/provider_token_source.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Rules audits/impact/rider-wipe-partway.md, Round 2 (supervisor SF-1,
/// SF-3, SF-4): what a refused sign-in leaves behind.

const _phoneA = '+46701234567';
const _phoneB = '+46701740650';
const _phoneC = '+46701112233';
const _cards = 'movera_saved_cards';

/// A server token whose `sub` is [rider] (contract C-1).
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

class _Provider implements ProviderTokenSource {
  @override
  Future<ProviderIdentityToken?> obtain(String provider) async =>
      ProviderIdentityToken(provider: provider, idToken: 'id-token-of-rider-b');
}

/// The server as far as sign-in goes, and the phone's token store.
class _Server {
  final tokens = MemoryTokenStore();

  /// Phones the server answers `isNewRider: true` for (once, as the real
  /// one does).
  final newRiders = <String>{};
  bool signOutFails = false;

  /// One entry per `POST /auth/sign-out`: what the phone still held when
  /// the request arrived, and the bearer token it carried.
  final signOuts = <({String? stored, String? bearer})>[];

  late final auth = AuthController(
    auth: AuthRepository(
      api: ApiClient(tokens: tokens, client: MockClient(_answer)),
      tokens: tokens,
    ),
    providerTokens: _Provider(),
  );

  Future<http.Response> _answer(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path.endsWith('/auth/otp/verify')) {
      final phone = (jsonDecode(request.body) as Map)['phone'] as String;
      return json({
        'accessToken': _token('rider-$phone'),
        'refreshToken': 'refresh-$phone',
        'isNewRider': newRiders.remove(phone),
      });
    }
    if (path.endsWith('/auth/provider')) {
      return json({
        'accessToken': _token('rider-$_phoneB'),
        'refreshToken': 'refresh-provider',
      });
    }
    if (path.endsWith('/auth/sign-out')) {
      signOuts.add((
        stored: await tokens.readAccess(),
        bearer: request.headers['Authorization'],
      ));
      if (signOutFails) throw http.ClientException('connection lost');
      return json(<String, Object>{});
    }
    return http.Response('{}', 404);
  }

  Future<OtpVerifyResult> verify(String phone) => auth.verifyOtp(
    challenge: OtpChallenge(
      phone: phone,
      requestId: 'q',
      sessionId: 's',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      retryAfter: Duration.zero,
    ),
    code: '1234',
  );
}

/// A phone that rider A used: A is recorded, A's cards are saved.
Future<_RemoveFails> _deviceOfRiderA() async {
  SharedPreferences.setMockInitialValues({});
  final store = _RemoveFails(<String, Object>{
    'flutter.$_cards': '[{"id":"c1","last4":"4242"}]',
    'flutter.movera_home_address': 'Rider A home',
  });
  final original = SharedPreferencesStorePlatform.instance;
  SharedPreferencesStorePlatform.instance = store;
  addTearDown(() => SharedPreferencesStorePlatform.instance = original);
  await (await SharedPreferences.getInstance()).reload();
  await UserDataWipe.enterSessionAs('sub:rider-$_phoneA');
  return store;
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

  test('a refused sign-in clears the phone\'s tokens BEFORE the server is '
      'told, and tells the server with the refused session', () async {
    final store = await _deviceOfRiderA();
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);
    final server = _Server();

    store.failing = _cards;
    await expectLater(
      server.verify(_phoneB),
      throwsA(isA<UserDataWipeIncomplete>()),
    );

    expect(server.signOuts, hasLength(1));
    expect(
      server.signOuts.single.stored,
      isNull,
      reason: 'a kill during the server call must not leave rider B\'s tokens',
    );
    expect(server.signOuts.single.bearer, 'Bearer ${_token('rider-$_phoneB')}');
    expect(await server.auth.hasSession(), isFalse);
    expect(
      (await _prefs()).getString(UserDataWipe.riderFingerprintKey),
      ownerA,
    );
  });

  test('the server sign-out throwing inside the refusal changes nothing: '
      'still refused, no session, rider A still recorded', () async {
    final store = await _deviceOfRiderA();
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);
    final server = _Server()..signOutFails = true;

    store.failing = _cards;
    await expectLater(
      server.verify(_phoneB),
      throwsA(isA<UserDataWipeIncomplete>()),
    );

    expect(server.signOuts, hasLength(1));
    expect(await server.auth.hasSession(), isFalse);
    expect(await server.tokens.readRefresh(), isNull);
    final prefs = await _prefs();
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);
    expect(prefs.getString(_cards), isNotNull, reason: 'precondition');
  });

  test('Apple / Google: a sign-in that meets a part-way wipe is refused '
      'the same way, and works once the wipe can finish', () async {
    final store = await _deviceOfRiderA();
    final ownerA = (await _prefs()).getString(UserDataWipe.riderFingerprintKey);
    final server = _Server();

    store.failing = _cards;
    await expectLater(
      server.auth.signIn(provider: 'apple'),
      throwsA(isA<UserDataWipeIncomplete>()),
    );
    expect(await server.auth.hasSession(), isFalse);
    expect(
      (await _prefs()).getString(UserDataWipe.riderFingerprintKey),
      ownerA,
    );

    store.failing = null;
    expect(
      await server.auth.signIn(provider: 'apple'),
      isA<ProviderSignedIn>(),
    );
    final prefs = await _prefs();
    expect(await server.auth.hasSession(), isTrue);
    expect(prefs.getString(_cards), isNull);
    expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
  });

  test('a new rider whose first sign-in is refused is still asked for a '
      'name after the next accepted one', () async {
    final store = await _deviceOfRiderA();
    final server = _Server()..newRiders.add(_phoneB);

    store.failing = _cards;
    await expectLater(
      server.verify(_phoneB),
      throwsA(isA<UserDataWipeIncomplete>()),
    );

    // The server says isNewRider once only.
    store.failing = null;
    final result = await server.verify(_phoneB);
    expect(result.isNewRider, isTrue, reason: 'the name screen opens');
    expect(
      await PendingRiderName.read(),
      isNotNull,
      reason: 'and a reload on it asks again',
    );

    // Asked once: the next sign-in of the same rider is a returning one.
    await PendingRiderName.clear();
    expect((await server.verify(_phoneB)).isNewRider, isFalse);
    expect(await PendingRiderName.read(), isNull);
  });

  test('a name already given is not asked again by a note that outlived '
      'its sign-in; another rider\'s note stays', () async {
    SharedPreferences.setMockInitialValues({});
    await UserDataWipe.enterSessionAs('sub:rider-$_phoneB');
    await UserDataWipe.noteNameOwed('sub:rider-$_phoneB');
    await UserDataWipe.nameGiven();
    expect(await UserDataWipe.takeNameOwed('sub:rider-$_phoneB'), isFalse);

    await UserDataWipe.noteNameOwed('sub:rider-$_phoneC');
    await UserDataWipe.nameGiven();
    expect(await UserDataWipe.takeNameOwed('sub:rider-$_phoneC'), isTrue);
  });

  test('the name owed by a refused new rider is not asked of another '
      'rider, and is still asked of the new rider later', () async {
    final store = await _deviceOfRiderA();
    final server = _Server()..newRiders.add(_phoneB);

    store.failing = _cards;
    await expectLater(
      server.verify(_phoneB),
      throwsA(isA<UserDataWipeIncomplete>()),
    );
    store.failing = null;

    expect((await server.verify(_phoneC)).isNewRider, isFalse);
    expect(await PendingRiderName.read(), isNull);

    expect((await server.verify(_phoneB)).isNewRider, isTrue);
    expect(await PendingRiderName.read(), isNotNull);
  });
}
