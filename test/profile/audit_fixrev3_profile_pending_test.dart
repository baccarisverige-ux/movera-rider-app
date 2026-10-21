// rider-fixrev3-3: a change the server never received (the server read or
// the PATCH failed at save time) survives a restart. The not-yet-sent fields
// used to live only in memory, so on the next launch the server copy was
// written over the device copy and the change was never sent.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts profile requests and can refuse reads, writes or both.
class _ProfileServer extends InProcessMockClient {
  int patches = 0;
  bool readsDown = false;
  bool writesDown = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == SyncedProfileRepository.path) {
      if (request.method == 'GET' && readsDown) failNext = true;
      if (request.method == 'PATCH') {
        patches++;
        if (writesDown) failNext = true;
      }
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  _ProfileServer serverWithAda() => _ProfileServer()
    ..riderProfile = {
      'name': 'Ada Lovelace',
      'language': 'sv',
      'consents': {
        'rideUpdates': true,
        'emailUpdates': false,
        'promotions': false,
      },
    };

  /// A fresh process over the same device storage.
  ProfileController launch(_ProfileServer server) => ProfileController(
    store: SyncedProfileRepository(
      api: ApiClient(client: server, env: demo),
    ),
  );

  test(
    'a change saved while the server read failed is sent after a restart',
    () async {
      final server = serverWithAda()..readsDown = true;
      final first = launch(server);
      await first.hydrate();
      await first.update(first.profile.copyWith(promotions: true));
      expect(server.patches, 0);
      expect(first.profile.promotions, isTrue);

      // The app is killed and launched again online.
      server.readsDown = false;
      final next = launch(server);
      await next.hydrateLocalThenServer();
      expect(next.profile.promotions, isTrue, reason: 'the device copy');
      await next.hydrate();
      expect(
        next.profile.promotions,
        isTrue,
        reason: 'kept over the server copy',
      );
      expect(next.profile.name, 'Ada Lovelace');
      expect(server.patches, 1);
      expect(server.riderProfile?['consents'], {
        'rideUpdates': true,
        'emailUpdates': false,
        'promotions': true,
      });
    },
  );

  test('a change whose PATCH failed is sent after a restart', () async {
    final server = serverWithAda();
    final first = launch(server);
    await first.hydrate();
    server.writesDown = true;
    await first.update(first.profile.copyWith(emailUpdates: true));
    expect(server.patches, 1);
    expect(server.riderProfile?['consents']?['emailUpdates'], isFalse);

    server.writesDown = false;
    final next = launch(server);
    await next.hydrate();
    expect(next.profile.emailUpdates, isTrue);
    expect(server.patches, 2);
    expect(server.riderProfile?['consents']?['emailUpdates'], isTrue);
  });

  test('a change the server has is not kept pending', () async {
    final server = serverWithAda();
    final first = launch(server);
    await first.hydrate();
    await first.update(first.profile.copyWith(language: 'fr'));
    expect(server.patches, 1);

    // Someone changed the language elsewhere before the next launch.
    server.riderProfile?['language'] = 'en';
    final next = launch(server);
    await next.hydrate();
    expect(next.profile.language, 'en');
    expect(server.patches, 1);
  });
}
