// rider-u195: after a reload, a Ride check whose alert failed came back as
// "Movera safety team alerted", and closing it sent alert:false, so the
// safety team was never alerted.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rideId = 'ride_u195';
const _answersPath = '/api/v1/safety/ridecheck/answers';

/// Refuses Ride check answers while [down], and records each body sent.
class _Client extends InProcessMockClient {
  bool down = false;
  final answers = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == _answersPath) {
      if (request is http.Request && request.body.isNotEmpty) {
        answers.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      if (down) failNext = true;
    }
    return super.send(request);
  }
}

class _NoRecorder implements SafetyRecorder {
  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> start(String recordingId) async {}
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {}
}

/// One app launch over the device's stored Safety data.
Future<RideCheckController> _launch(_Client client) async {
  SafetyStore.resetShared();
  SafetyRepository.resetShared();
  SafetyController.resetShared();
  final store = SafetyStore(
    local: PreferencesSafetyLocalDataSource(),
    remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
  );
  final safety = SafetyController(
    session: store,
    emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    audio: SafetyAudioService(recorder: _NoRecorder(), store: store),
  );
  await safety.load();
  final rideCheck = RideCheckController.forSafety(safety);
  rideCheck.attachTrip(
    const RideCheckTripContext(rideId: _rideId, status: 'tripInProgress'),
    const RideCheckPlan(
      pickup: GeoPoint(59.3429, 18.0496),
      destination: GeoPoint(59.3600, 18.0000),
    ),
  );
  return rideCheck;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
  });

  Future<void> reloadAndClose(
    Future<void> Function(RideCheckController) answer,
  ) async {
    final client = _Client()..down = true;
    final first = await _launch(client);
    expect(
      await first.open(RideCheckTrigger.longStop, rideId: _rideId),
      RideCheckOpenResult.shown,
    );
    await answer(first);
    await _settle();
    expect(first.session!.alertState, RideCheckAlertState.failed);

    // The app is reloaded while the card is up and the alert has failed.
    final second = await _launch(client);
    await second.resume(_rideId);
    expect(second.session, isNotNull);
    expect(
      second.session!.alertState,
      RideCheckAlertState.failed,
      reason: 'the card must not say the team was alerted',
    );

    // Back online: closing the card sends the alert.
    client
      ..down = false
      ..answers.clear();
    second.done();
    await _settle();
    expect(client.answers.last['final'], isTrue);
    expect(client.answers.last['alert'], isTrue);
    expect(safetyMockForProcess().rideCheckAlerts, isNotEmpty);
  }

  test(
    'Call 112 with a failed alert: restored as failed, alerted on close',
    () => reloadAndClose((rideCheck) => rideCheck.call112()),
  );

  test(
    'a red row with a failed alert: restored as failed, alerted on close',
    () => reloadAndClose((rideCheck) async {
      final red = rideCheck.session!.rows.firstWhere((row) => row.red);
      rideCheck.chooseRow(red.id);
    }),
  );

  test('a check with no alert stays without one after a reload', () async {
    final client = _Client();
    final first = await _launch(client);
    await first.open(RideCheckTrigger.longStop, rideId: _rideId);
    final calm = first.session!.rows.firstWhere((row) => !row.red);
    first.chooseRow(calm.id);
    await _settle();
    final second = await _launch(client);
    await second.resume(_rideId);
    // An answer that is not an alert is only saved once the card closes.
    if (second.session != null) {
      expect(second.session!.alertState, RideCheckAlertState.none);
    }
    expect(safetyMockForProcess().rideCheckAlerts, isEmpty);
  });
}
