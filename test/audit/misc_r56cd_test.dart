import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.6 parts c + d: everything else (low). One test per bug.

/// Storage whose writes fail once [fail] is set (quota, blocked storage).
class _FlakyStorage extends MemoryReservationStorage {
  bool fail = false;

  @override
  Future<void> write(String json) async {
    if (fail) throw StateError('storage full');
    await super.write(json);
  }
}

final _pickupAt = DateTime(2026, 9, 23, 6, 55);

ReservationDraft _draft({String? note}) => ReservationDraft(
  scheduledPickupAt: _pickupAt,
  estimatedDropoffAt: _pickupAt.add(const Duration(minutes: 30)),
  pickup: const ReservationPlace(label: 'Klockarvägen 37'),
  destination: const ReservationPlace(label: 'Arlanda Express'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 522,
  paymentMethod: 'Cash',
  note: note,
);

Future<ReservationController> _reservations(ReservationStorage storage) async {
  final c = ReservationController(
    store: LocalReservationRepository(storage: storage, nextId: () => 'rsv_1'),
  );
  await c.create(_draft());
  return c;
}

/// A microphone that captures [path] (null: nothing was written).
class _Recorder implements SafetyRecorder {
  String? path = '/device/safety/take.m4a';
  bool live = false;

  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start(String recordingId) async => live = true;
  @override
  Future<String?> stop() async {
    live = false;
    return path;
  }

  @override
  Future<void> cancel() async => live = false;
  @override
  Future<void> delete(String path) async {}
}

/// A Safety store on the in-process stand-in server, with its cache.
({SafetyStore store, PreferencesSafetyLocalDataSource local}) _store({
  bool offline = false,
}) {
  final local = PreferencesSafetyLocalDataSource(memoryOnly: true);
  final client = offline
      ? MockClient((_) async => throw http.ClientException('offline'))
      : InProcessMockClient();
  final store = SafetyStore(
    local: local,
    remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
  );
  return (store: store, local: local);
}

/// A fresh Safety Kit on the in-process stand-in server.
Future<SafetyController> _safety({
  Map<String, dynamic>? triggers,
  ApiClient? api,
}) async {
  SharedPreferences.setMockInitialValues({});
  resetSafetyMockForProcess();
  SafetyStore.resetShared();
  SafetyRepository.resetShared();
  SafetyController.resetShared();
  if (triggers != null) {
    safetyMockForProcess().rideCheck['triggers'] = {
      ...SafetyMockApi.defaultRideCheckTriggers(),
      ...triggers,
    };
  }
  final safety = SafetyController(
    session: SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        api ?? ApiClient(client: InProcessMockClient()),
      ),
    ),
    emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
  );
  await safety.load();
  return safety;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('rider-j8-4: a 0.35 € edit is a real price change', () {
    const change = ReservationPriceChange(
      previous: 12.35,
      next: 12.70,
      currency: 'EUR',
    );
    expect(change.unchanged, isFalse);
    expect(change.summary, contains('0,35 €'));
  });

  testWidgets('rider-j8-6: a failed no-driver resolve says so', (tester) async {
    final storage = _FlakyStorage();
    final c = await _reservations(storage);
    var rebooked = 0;
    final late = _pickupAt.add(const Duration(minutes: 6));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeReservationChrono(
            controller: c,
            now: () => late,
            onRebook: () => rebooked++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    storage.fail = true;
    await tester.tap(find.byKey(const Key('reservation-no-driver-rebook')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(rebooked, 0);
    expect(c.byId('rsv_1')!.status.isUpcoming, isTrue);
  });

  test('rider-u164: live ride notes match whole labels only', () async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_1',
      ),
    );
    final ride = await c.create(
      _draft(note: 'Petra will meet the driver · Bags 3+'),
    );
    final notes = ReservationLiveRide.notesOf(ride);
    expect(notes.bagLevel, 2);
    expect(notes.pet, isFalse);
  });

  test('rider-u193: the Long stop demo opens the long-stop card', () async {
    final safety = await _safety(
      triggers: {
        'longStopMinutes': 15,
        'longStop': {'enabled': true, 'minutes': 15},
      },
    );
    final rideCheck = RideCheckController.forSafety(safety);
    addTearDown(rideCheck.dispose);
    expect(
      await rideCheck.playDemo(RideCheckTrigger.longStop, rideId: 'demo'),
      RideCheckOpenResult.shown,
    );
    expect(rideCheck.session!.trigger, RideCheckTrigger.longStop);
  });

  test('rider-u200: a failed stop leaves no orphan recording', () async {
    resetSafetyMockForProcess();
    final (:store, :local) = _store();
    await store.load();
    final recorder = _Recorder()..path = null;
    final audio = SafetyAudioService(recorder: recorder, store: store);
    await audio.start(rideId: 'ride_a');
    await expectLater(audio.stop(), throwsA(isA<SafetyAudioException>()));
    expect((await local.load()).recordings, isEmpty);

    // The server lost the take: it is still kept here with its file.
    recorder.path = '/device/safety/take.m4a';
    await audio.start(rideId: 'ride_a');
    resetSafetyMockForProcess();
    final saved = await audio.stop();
    expect(saved.localPath, '/device/safety/take.m4a');
    expect((await local.load()).recordings.single.endedAt, isNotNull);
  });

  test('rider-u207: Kit audio starts offline and keeps one entry', () async {
    resetSafetyMockForProcess();
    final online = _store();
    await online.store.load();
    await SafetyAudioService(
      recorder: _Recorder(),
      store: online.store,
    ).start(rideId: 'ride_a');
    expect((await online.local.load()).recordings, hasLength(1));

    final offline = _store(offline: true);
    final audio = SafetyAudioService(
      recorder: _Recorder(),
      store: offline.store,
    );
    await audio.start(rideId: 'ride_a');
    expect(audio.isRecording, isTrue);
  });

  test('rider-u201: session expiry turns the microphone off', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    final (:store, local: _) = _store();
    final recorder = _Recorder();
    final safety = SafetyController(
      session: store,
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    SafetyController.sharedForTest = safety;
    addTearDown(() => SafetyController.sharedForTest = null);
    await safety.audio.start(rideId: 'ride_a', deviceOnly: true);

    await AppScope.instance.tokens.save(
      access: 'u201-expired-access',
      refresh: 'u201-rejected-refresh',
    );
    await expectLater(
      AppScope.instance.api.post(
        '/api/v1/auth/refresh',
        body: {'refreshToken': 'u201-rejected-refresh'},
      ),
      throwsA(isA<ApiError>()),
    );
    expect(recorder.live, isFalse);
    expect(safety.audio.isRecording, isFalse);
  });
}
