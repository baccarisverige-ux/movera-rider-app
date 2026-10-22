// rider-u150: a 422 from the profile PATCH (the server refuses a name over
// 80 characters) was kept as "pending, retry later". The screen showed the
// save as done, and every later save resent the same refused name, so no
// consent or language change reached the server again.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileServer extends InProcessMockClient {
  int patches = 0;
  bool writesDown = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == SyncedProfileRepository.path &&
        request.method == 'PATCH') {
      patches++;
      if (writesDown) failNext = true;
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
  final tooLong = '${'A' * 40} ${'B' * 40}';

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

  (ProfileController, SyncedProfileRepository) launch(_ProfileServer server) {
    final repository = SyncedProfileRepository(
      api: ApiClient(client: server, env: demo),
    );
    return (ProfileController(store: repository), repository);
  }

  test('a refused name is reported, not kept pending', () async {
    final server = serverWithAda();
    final (controller, repository) = launch(server);
    await controller.hydrate();
    var notified = 0;
    controller.addListener(() => notified++);

    await expectLater(
      controller.update(controller.profile.copyWith(name: tooLong)),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 422)),
    );

    expect(repository.syncPending, isFalse);
    // The device copy goes back to what the server holds.
    expect(controller.profile.name, 'Ada Lovelace');
    expect(server.riderProfile?['name'], 'Ada Lovelace');
    expect(notified, greaterThan(0));
  });

  test('a later consent change still reaches the server', () async {
    final server = serverWithAda();
    final (controller, repository) = launch(server);
    await controller.hydrate();
    await expectLater(
      controller.update(controller.profile.copyWith(name: tooLong)),
      throwsA(isA<ApiError>()),
    );

    await controller.update(controller.profile.copyWith(promotions: true));

    expect(repository.syncPending, isFalse);
    expect((server.riderProfile?['consents'] as Map)['promotions'], isTrue);
    expect(server.riderProfile?['name'], 'Ada Lovelace');
  });

  test(
    'a refused change left pending by an older version is dropped',
    () async {
      SharedPreferences.setMockInitialValues({
        'movera_profile_v1': jsonEncode({
          'name': tooLong,
          'language': 'sv',
          'rideUpdates': true,
          'emailUpdates': false,
          'promotions': false,
        }),
        'movera_profile_v1.pending': <String>['name'],
      });
      final server = serverWithAda();
      final (controller, repository) = launch(server);

      await controller.hydrate();

      expect(repository.syncPending, isFalse);
      expect(controller.profile.name, 'Ada Lovelace');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('movera_profile_v1.pending'), isNull);

      await controller.update(controller.profile.copyWith(promotions: true));
      expect((server.riderProfile?['consents'] as Map)['promotions'], isTrue);
    },
  );

  test('a network failure is still kept to send later', () async {
    final server = serverWithAda();
    final (controller, repository) = launch(server);
    await controller.hydrate();
    server.writesDown = true;

    await controller.update(controller.profile.copyWith(promotions: true));

    expect(repository.syncPending, isTrue);
    expect(controller.profile.promotions, isTrue);
  });
}
