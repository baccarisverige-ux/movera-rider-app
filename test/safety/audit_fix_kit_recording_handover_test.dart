// rider-u212 / rider-u214: a Ride check card opening pops the Safety Kit
// sheet, and the kit's dispose stopped the rider's ongoing Safety Kit
// recording at the moment Ride check had just detected something wrong.
// The card now takes the running recording over and shows it as running.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/safety/presentation/safety_audio_option.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rideId = 'ride_u212';

class _Recorder implements SafetyRecorder {
  bool recording = false;
  int stops = 0;
  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start(String recordingId) async => recording = true;
  @override
  Future<String?> stop() async {
    stops++;
    recording = false;
    return '/device/safety/rec.m4a';
  }

  @override
  Future<void> cancel() async => recording = false;
  @override
  Future<void> delete(String path) async {}
}

/// Owner decision 10 hides "Record audio" by default; the recording tests
/// turn the option back on through its test seam.
void _withAudioOption() {
  SafetyAudioOption.debugEnabled = true;
  addTearDown(() => SafetyAudioOption.debugEnabled = null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late _Recorder recorder;
  late SafetyController safety;
  late RideCheckController rideCheck;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });
  tearDown(() => rideCheck.dispose());

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('a Safety Kit recording keeps running when a card opens', (
    tester,
  ) async {
    _withAudioOption();
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    recorder = _Recorder();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    await tester.runAsync(safety.load);
    rideCheck = RideCheckController.forSafety(safety);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: _rideId),
      const RideCheckPlan(
        pickup: GeoPoint(59.3429, 18.0496),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: RideCheckLayer(rideId: _rideId, controller: rideCheck),
        ),
      ),
    );
    unawaited(
      MoveraSheet.show<void>(
        context: navigator.currentContext!,
        builder: (_) => RideSafetyKitSheet(rideId: _rideId, controller: safety),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(recorder.recording, isTrue);

    // The car stops off-route: the long-stop card opens and the kit closes.
    await rideCheck.open(RideCheckTrigger.longStop, rideId: _rideId);
    await frames(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);
    expect(find.byType(RideSafetyKitSheet), findsNothing);

    expect(recorder.stops, 0, reason: 'the recording must not stop');
    expect(recorder.recording, isTrue);
    expect(rideCheck.recording, isTrue);
    expect(
      find.textContaining('Recording 0:', findRichText: true),
      findsOneWidget,
    );

    // The card's own control stops it.
    final record = find.byKey(const ValueKey<String>('ride-check-record'));
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(tester);
    expect(recorder.stops, 1);
  });
}
