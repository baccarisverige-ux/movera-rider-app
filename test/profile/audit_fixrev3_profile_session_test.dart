// rider-fixrev3-1: a server read started for the signed-out rider must not
// land in the next rider's profile. Sign-out (UserDataWipe) wipes the device
// copy and calls clearLocal(); a GET /rider/profile still in flight for the
// previous rider used to be joined by the next rider's hydrate() or, when it
// answered after the wipe, re-written into the cache with the server marked
// as known, so the next rider was greeted by name as the previous one and
// PATCHed that name onto their own server profile.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A slow network: the GET answer is computed when the request arrives (the
/// profile of the rider signed in then) and delivered when the test says so.
class _SlowProfileServer extends InProcessMockClient {
  int gets = 0;
  int patches = 0;
  final List<Completer<void>> _held = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == SyncedProfileRepository.path) {
      if (request.method == 'GET') {
        gets++;
        final response = await super.send(request);
        final gate = Completer<void>();
        _held.add(gate);
        await gate.future;
        return response;
      }
      if (request.method == 'PATCH') patches++;
    }
    return super.send(request);
  }

  /// Lets every held answer through.
  void release() {
    for (final gate in _held) {
      if (!gate.isCompleted) gate.complete();
    }
    _held.clear();
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  const ada = {
    'name': 'Ada Lovelace',
    'language': 'sv',
    'consents': {
      'rideUpdates': true,
      'emailUpdates': false,
      'promotions': true,
    },
  };
  const grace = {
    'name': 'Grace Hopper',
    'language': 'en',
    'consents': {
      'rideUpdates': true,
      'emailUpdates': true,
      'promotions': false,
    },
  };

  ProfileController controllerFor(_SlowProfileServer server) =>
      ProfileController(
        store: SyncedProfileRepository(
          api: ApiClient(client: server, env: demo),
        ),
      );

  /// Sign-out while rider A's read is pending: UserDataWipe removes the
  /// device copy and clears the in-memory profile.
  void signOut(ProfileController controller) {
    SharedPreferences.setMockInitialValues({});
    controller.clearLocal();
  }

  test(
    'the next rider does not join the previous rider\'s pending read',
    () async {
      final server = _SlowProfileServer()..riderProfile = Map.of(ada);
      final controller = controllerFor(server);
      final riderA = controller.hydrate();
      await _settle();
      expect(server.gets, 1, reason: 'rider A\'s read is in flight');

      signOut(controller);
      server.riderProfile = Map.of(grace);
      final riderB = controller.hydrate();
      await _settle();
      expect(server.gets, 2, reason: 'rider B gets her own read');

      server.release();
      await Future.wait([riderA, riderB]);
      expect(controller.profile.name, 'Grace Hopper');
      expect(controller.profile.language, 'en');
      expect(controller.profile.promotions, isFalse);

      await controller.update(controller.profile.copyWith(promotions: true));
      expect(server.riderProfile?['name'], 'Grace Hopper');
      expect(server.riderProfile?['consents'], {
        'rideUpdates': true,
        'emailUpdates': true,
        'promotions': true,
      });
    },
  );

  test('a read answering after sign-out is dropped', () async {
    final server = _SlowProfileServer()..riderProfile = Map.of(ada);
    final controller = controllerFor(server);
    final riderA = controller.hydrate();
    await _settle();

    signOut(controller);
    server.release();
    await riderA;
    expect(controller.profile.name, '', reason: 'A\'s answer is not kept');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('movera_profile_v1'), isNull);

    server.riderProfile = Map.of(grace);
    final riderB = controller.hydrate();
    await _settle();
    expect(server.gets, 2, reason: 'the server is not known for rider B');
    server.release();
    await riderB;
    expect(controller.profile.name, 'Grace Hopper');

    await controller.update(controller.profile.copyWith(language: 'fr'));
    expect(server.patches, 1);
    expect(server.riderProfile?['name'], 'Grace Hopper');
    expect(server.riderProfile?['language'], 'fr');
  });
}
