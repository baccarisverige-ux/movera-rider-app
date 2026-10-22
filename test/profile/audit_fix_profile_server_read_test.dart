// rider-u148 / rider-u149: the server profile was never read, so after a
// sign-out (or on a new device) the empty device copy was PATCHed over the
// rider's name and consents on the server.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts profile requests and can refuse every one of them.
class _ProfileServer extends InProcessMockClient {
  int patches = 0;
  bool down = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == SyncedProfileRepository.path) {
      if (request.method == 'PATCH') patches++;
      if (down) failNext = true;
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // An empty device: signed out and back in, or a new phone.
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
        'promotions': true,
      },
    };

  ProfileController controllerFor(_ProfileServer server) => ProfileController(
    store: SyncedProfileRepository(
      api: ApiClient(client: server, env: demo),
    ),
  );

  test('a returning rider gets the server profile on the device', () async {
    final server = serverWithAda();
    final controller = controllerFor(server);
    await controller.hydrate();
    expect(controller.profile.name, 'Ada Lovelace');
    expect(controller.profile.language, 'sv');
    expect(controller.profile.emailUpdates, isFalse);
    expect(controller.profile.promotions, isTrue);
  });

  test('the first save keeps the server name and consents', () async {
    final server = serverWithAda();
    final controller = controllerFor(server);
    // The save comes before any hydrate, from a cache at its defaults.
    await controller.update(controller.profile.copyWith(language: 'fr'));
    expect(server.riderProfile?['name'], 'Ada Lovelace');
    expect(server.riderProfile?['language'], 'fr');
    expect(server.riderProfile?['consents'], {
      'rideUpdates': true,
      'emailUpdates': false,
      'promotions': true,
    });
    expect(controller.profile.name, 'Ada Lovelace');
  });

  test(
    'offline, a save sends no blank profile and is sent once known',
    () async {
      final server = serverWithAda()..down = true;
      final controller = controllerFor(server);
      await controller.hydrate();
      await controller.update(controller.profile.copyWith(rideUpdates: false));
      expect(server.patches, 0, reason: 'the server profile is not known yet');
      expect(server.riderProfile?['name'], 'Ada Lovelace');
      expect(controller.profile.rideUpdates, isFalse);

      server.down = false;
      await controller.hydrate();
      expect(server.riderProfile?['name'], 'Ada Lovelace');
      expect(server.riderProfile?['consents'], {
        'rideUpdates': false,
        'emailUpdates': false,
        'promotions': true,
      });
      expect(controller.profile.name, 'Ada Lovelace');
      expect(controller.profile.rideUpdates, isFalse);
    },
  );

  test('after sign-out the next rider reads the server again', () async {
    final server = serverWithAda();
    final controller = controllerFor(server);
    await controller.hydrate();
    // Sign-out: UserDataWipe removes the device copy, then clearLocal.
    SharedPreferences.setMockInitialValues({});
    controller.clearLocal();
    expect(controller.profile.name, '');
    server.riderProfile = {'name': 'Grace Hopper', 'language': 'en'};
    await controller.update(controller.profile.copyWith(promotions: true));
    expect(server.riderProfile?['name'], 'Grace Hopper');
    expect(controller.profile.name, 'Grace Hopper');
  });
}
