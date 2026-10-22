import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/safety/presentation/safety_audio_option.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// A backend that assigns its own contact ids (FLOW-20).
class _ServerIdRemote extends ApiSafetyRemoteDataSource {
  _ServerIdRemote(super.api);
  @override
  Future<EmergencyContact> createContact(
    EmergencyContact contact, {
    String? idempotencyKey,
  }) async {
    final echoed = await super.createContact(
      contact,
      idempotencyKey: idempotencyKey,
    );
    return echoed.copyWith(id: 'srv_1');
  }
}

SafetyStore _store({SafetyRemoteDataSource? remote}) => SafetyStore(
  local: PreferencesSafetyLocalDataSource(memoryOnly: true),
  remote:
      remote ??
      ApiSafetyRemoteDataSource(ApiClient(client: InProcessMockClient())),
);

/// Owner decision 10 hides "Record audio" by default; the recording tests
/// turn the option back on through its test seam.
void _withAudioOption() {
  SafetyAudioOption.debugEnabled = true;
  addTearDown(() => SafetyAudioOption.debugEnabled = null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
  });
  tearDown(() => SafetyController.sharedForTest = null);

  testWidgets('FLOW-6: closing the Safety Kit stops and saves the recording', (
    tester,
  ) async {
    _withAudioOption();
    final recorder = _Recorder();
    final store = _store();
    final ctl = SafetyController(
      session: store,
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    await tester.runAsync(ctl.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(rideId: 'ride_a', controller: ctl),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(recorder.recording, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(recorder.recording, isFalse);
    expect(recorder.stops, 1);
    expect(ctl.audio.isRecording, isFalse);
  });

  test(
    'FLOW-6: the ride ending stops a recording that is still running',
    () async {
      final recorder = _Recorder();
      final store = _store();
      final ctl = SafetyController(
        session: store,
        audio: SafetyAudioService(recorder: recorder, store: store),
      );
      SafetyController.sharedForTest = ctl;
      await ctl.audio.start(rideId: 'ride_b');
      expect(recorder.recording, isTrue);

      AppScope.instance.ride.rideId = 'ride_b';
      await ActiveRideController().markCompleted(RideStatus.tripCompleted);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(recorder.recording, isFalse);
      expect(recorder.stops, 1);
    },
  );

  test(
    'FLOW-20: a server-assigned contact id replaces the optimistic row',
    () async {
      final store = _store(
        remote: _ServerIdRemote(ApiClient(client: InProcessMockClient())),
      );
      await store.load();
      await store.createContact(name: 'Kim', phone: '0701234567');
      expect(store.contacts, hasLength(1));
      expect(store.contacts.single.id, 'srv_1');
    },
  );

  test('FLOW-9: demo Safety contacts and PIN survive a reload', () async {
    SafetyStore launch() => SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient(persistSafety: true)),
      ),
    );
    final first = launch();
    await first.load();
    await first.createContact(name: 'Kim', phone: '0701234567');
    final pin = first.pin;

    // A reload: a new process-level mock and a fresh store.
    resetSafetyMockForProcess();
    final second = launch();
    await second.load();
    expect(second.contacts.map((c) => c.name), ['Kim']);
    expect(second.pin.pin, isNotEmpty);
    expect(second.pin.pin, pin.pin);
  });

  testWidgets('FLOW-15: deleting a contact asks first', (tester) async {
    final store = _store();
    final ctl = SafetyController(session: store);
    await tester.runAsync(() async {
      await ctl.load();
      await ctl.addContact(name: 'Kim', phone: '0701234567');
    });
    await tester.pumpWidget(
      MaterialApp(home: EmergencyContactsPage(controller: ctl)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Kim?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ctl.contacts, hasLength(1));
  });

  testWidgets('FLOW-15: a failed primary change is reported', (tester) async {
    final store = _store();
    final ctl = SafetyController(session: store);
    await tester.runAsync(() async {
      await ctl.load();
      await ctl.addContact(name: 'Kim', phone: '0701234567');
      await ctl.addContact(name: 'Sam', phone: '0707654321');
    });
    await tester.pumpWidget(
      MaterialApp(home: EmergencyContactsPage(controller: ctl)),
    );
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make primary'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not make Sam your primary contact. Try again.'),
      findsOneWidget,
    );
  });
}
