import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/phone_e164.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
import 'package:movera_rider/features/safety/presentation/pin_verification_page.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/safety/presentation/safety_audio_option.dart';
import 'package:shared_preferences/shared_preferences.dart';

SafetyController buildController({SafetyStore? store}) {
  resetSafetyMockForProcess();
  SafetyStore.resetShared();
  SafetyRepository.resetShared();
  SafetyController.resetShared();
  final client = InProcessMockClient();
  final session =
      store ??
      SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
      );
  return SafetyController(session: session);
}

class TestSafetyRecorder implements SafetyRecorder {
  bool permissionGranted = false;
  String? capturedPath = '/device/safety/recording.m4a';
  int permissionRequests = 0;
  int starts = 0;
  int stops = 0;
  final deletedPaths = <String>[];

  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> start(String recordingId) async {
    starts++;
  }

  @override
  Future<String?> stop() async {
    stops++;
    return capturedPath;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {
    deletedPaths.add(path);
  }
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    // The phone's GPS comes from the platform; these tests have none.
    SafetyController.locateForSos = () async => null;
  });
  tearDown(() => SafetyController.locateForSos = lastSosPosition);

  test('Waiting maskedCall still records on shared repository', () {
    SafetyController().record(SafetyKind.maskedCall);
    expect(SafetyController().events.single.kind, SafetyKind.maskedCall);
  });

  testWidgets('Safety Hub opens and loads persisted state', (tester) async {
    final ctl = buildController();
    await ctl.load();
    await tester.pumpWidget(MaterialApp(home: SafetyHub(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.text('Safety preferences'), findsOneWidget);
    expect(find.text('PIN verification'), findsOneWidget);
    for (final label in const [
      'PIN verification',
      'Emergency contacts',
      'Share trip status',
      'Trip check',
    ]) {
      // UI-7: the row reads its title first, then its subtitle and status.
      final row = find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}, '));
      final data = tester.getSemantics(row).getSemanticsData();
      expect(data.label, startsWith('$label, '), reason: label);
      expect(
        data.flagsCollection.isButton,
        isTrue,
        reason: '$label should be a button',
      );
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$label should be actionable',
      );
    }
    expect(find.text('Call 112'), findsNothing);
    expect(find.text('Record audio'), findsNothing);
    await tester.pumpWidget(MaterialApp(home: SafetyHub(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.text('Safety preferences'), findsOneWidget);
  });

  testWidgets('every Safety Hub row opens its real destination page', (
    tester,
  ) async {
    for (final route in const <(String, String)>[
      ('PIN verification', 'Verify rides with a PIN'),
      ('Emergency contacts', 'No emergency contacts yet'),
      ('Share trip status', 'Trip sharing'),
      ('Trip check', 'Trip check alerts'),
    ]) {
      final ctl = buildController();
      await ctl.load();
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: SafetyHub(controller: ctl),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.bySemanticsLabel(
        RegExp('^${RegExp.escape(route.$1)}, '),
      );
      expect(row, findsOneWidget, reason: route.$1);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text(route.$2), findsOneWidget, reason: route.$1);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('PIN page shows a framed 4-digit cadre', (tester) async {
    final ctl = buildController();
    await ctl.load();
    await tester.pumpWidget(
      MaterialApp(home: PinVerificationPage(controller: ctl)),
    );
    await tester.pumpAndSettle();
    expect(find.text('YOUR PIN'), findsOneWidget);
    expect(find.text('Verify rides with a PIN'), findsOneWidget);
    expect(find.text('Change PIN'), findsOneWidget);
    for (final digit in ctl.pin.pin.split('')) {
      expect(find.text(digit), findsWidgets);
    }
  });

  // ARCH-22: verifying a PIN is the driver app's call, so the rider client
  // has no verify method any more; see audit_fix_backend_seams_test.dart.
  test('PIN generate enable disable rotate persist', () async {
    final ctl = buildController();
    await ctl.load();
    expect(ctl.preferences.pinRequired, isFalse);
    expect(RegExp(r'^\d{4}$').hasMatch(ctl.pin.pin), isTrue);
    final first = ctl.pin.pin;
    await ctl.setPinRequired(true);
    expect(ctl.preferences.pinRequired, isTrue);
    await ctl.rotatePin();
    expect(ctl.pin.pin.length, 4);
    expect(ctl.pin.pin, isNot(first));
    await ctl.setPinRequired(false);
    expect(ctl.preferences.pinRequired, isFalse);
  });

  test('PIN DTO parsing', () {
    final parsed = RidePin.fromJson({
      'pinId': 'pin_1',
      'userId': 'rider-local',
      'pin': '4242',
      'required': true,
      'version': 2,
    });
    expect(parsed.pin, '4242');
    expect(parsed.requiredForStart, isTrue);
    expect(RidePin.fromJson({'pin': 'nope'}).pin, isEmpty);
    expect(RidePin.fromJson(null).isAvailable, isFalse);
    expect(SafetyPreferences.fromJson(null).pinRequired, isFalse);
  });

  test('emergency contacts CRUD primary duplicate and invalid phone', () async {
    final ctl = buildController();
    await ctl.load();
    await ctl.addContact(
      name: 'Sam',
      phone: '0701111111',
      relationship: 'Friend',
    );
    expect(ctl.contacts.single.isPrimary, isTrue);
    expect(ctl.contacts.single.phoneE164, '+46701111111');
    await ctl.addContact(
      name: 'Kim',
      phone: '+46702222222',
      relationship: 'Family',
    );
    expect(ctl.contacts, hasLength(2));
    final kim = ctl.contacts.firstWhere((c) => c.name == 'Kim');
    await ctl.makePrimary(kim.id);
    expect(ctl.contacts.where((c) => c.isPrimary).single.name, 'Kim');
    expect(
      () => ctl.addContact(name: 'Dup', phone: '0701111111'),
      throwsA(isA<SafetyException>()),
    );
    expect(
      () => ctl.addContact(name: 'Bad', phone: '123'),
      throwsA(isA<SafetyException>()),
    );
    await ctl.removeContact(ctl.contacts.firstWhere((c) => c.name == 'Sam').id);
    expect(ctl.contacts, hasLength(1));
    expect(ctl.contacts.single.isPrimary, isTrue);
  });

  test('max 5 contacts', () async {
    final ctl = buildController();
    await ctl.load();
    for (var i = 0; i < 5; i++) {
      await ctl.addContact(name: 'C$i', phone: '070100000$i');
    }
    expect(
      () => ctl.addContact(name: 'Extra', phone: '0709999999'),
      throwsA(isA<SafetyException>()),
    );
  });

  test('SwedishPhone E.164', () {
    expect(SwedishPhone.toE164('0701234567'), '+46701234567');
    expect(SwedishPhone.toE164('+46 70-123 45 67'), '+46701234567');
    expect(SwedishPhone.toE164('0046701234567'), '+46701234567');
    expect(SwedishPhone.toE164('123'), isNull);
  });

  test('trip share preferences start stop without fake URL', () async {
    final ctl = buildController();
    await ctl.load();
    await ctl.setTripShare(enabled: true, mode: TripShareMode.auto);
    expect(ctl.preferences.tripShareEnabled, isTrue);
    expect(() => ctl.startShare(''), throwsA(isA<SafetyException>()));
    final share = await ctl.startShare('ride_qa');
    expect(share.isActive, isTrue);
    expect(share.shareToken, isNotNull);
    expect(share.shareToken!.startsWith('http'), isFalse);
    await ctl.stopShare('ride_qa');
  });

  test('expired share DTO', () {
    final share = TripShare.fromJson({
      'shareId': 's1',
      'rideId': 'r1',
      'userId': 'rider-local',
      'isActive': true,
      'expiresAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    });
    expect(share.expired, isTrue);
  });

  test(
    'RideCheck enable deterministic events duplicate stale resolve',
    () async {
      final ctl = buildController();
      await ctl.load();
      await ctl.setRideCheck(true);
      expect(ctl.rideCheckPolicy.enabled, isTrue);
      final first = await ctl.rideCheck.unexpectedStop();
      final dup = await ctl.rideCheck.simulate(
        type: RideCheckEventType.unexpectedStop,
        eventId: first.eventId,
      );
      expect(dup.eventId, first.eventId);
      expect(
        ctl.rideCheck.events().where((e) => e.eventId == first.eventId),
        hasLength(1),
      );
      await ctl.rideCheck.resolve(first);
      final stale = await ctl.rideCheck.simulate(
        type: RideCheckEventType.routeDeviation,
        eventId: 'ev_stale',
        at: first.at.subtract(const Duration(minutes: 1)),
      );
      expect(stale.status, RideCheckStatus.stale);
      final live = await ctl.rideCheck.routeDeviation();
      expect(live.status, RideCheckStatus.pending);
    },
  );

  testWidgets(
    'a server RideCheck alert opens the Ride check card (not the Safety Kit) and sends resolution',
    (tester) async {
      final store = SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      );
      final ctl = SafetyController(session: store);
      await ctl.load();
      final alert = await ctl.rideCheck.unexpectedStop(rideId: 'ride_alert');

      // The Safety Kit no longer lists pending checks.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideSafetyKitSheet(rideId: 'ride_alert', controller: ctl),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RideCheck alert'), findsNothing);
      expect(find.text("I'm okay"), findsNothing);

      // The trip screen shows it as the Ride check card.
      final rideCheck = RideCheckController.forSafety(ctl);
      addTearDown(rideCheck.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideCheckLayer(rideId: 'ride_alert', controller: rideCheck),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('Is everything OK?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('ride-check-ok')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('Is everything OK?'), findsNothing);

      final confirmed = await ctl.rideCheck.refresh('ride_alert');
      expect(confirmed.single.eventId, alert.eventId);
      expect(confirmed.single.status, RideCheckStatus.resolved);
    },
  );

  test('failed SOS is not recorded as registered', () async {
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final ctl = SafetyController(session: store);
    await ctl.load();
    expect(await ctl.sos(), isFalse);
    store.failNextWrite = true;
    await expectLater(
      ctl.sos(rideId: 'ride_sos_failure'),
      throwsA(isA<SafetyException>()),
    );
    expect(ctl.events.where((event) => event.kind == SafetyKind.sos), isEmpty);
    expect(await ctl.rideCheck.refresh('ride_sos_failure'), isEmpty);
  });

  testWidgets(
    'Safety Kit distinguishes opened dialer from failed SOS registration',
    (tester) async {
      final store = SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      );
      final dialer = RecordingEmergencyDialer();
      final ctl = SafetyController(
        session: store,
        emergency: EmergencyCallService(dialer: dialer),
      );
      await ctl.load();
      store.failNextWrite = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideSafetyKitSheet(
              rideId: 'ride_failed_sos',
              controller: ctl,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact 112'));
      await tester.pumpAndSettle();
      expect(dialer.calls, ['112']);
      expect(
        find.text(
          'Phone dialer opened, but Movera could not register your SOS.',
        ),
        findsOneWidget,
      );
    },
  );

  test('emergency call is never automatic', () async {
    final dialer = RecordingEmergencyDialer();
    final service = EmergencyCallService(dialer: dialer);
    expect(service.explicitCallCount, 0);
    expect(dialer.calls, isEmpty);
    await service.callEmergencyNumber();
    expect(dialer.calls, ['112']);
    expect(service.explicitCallCount, 1);
  });

  test('audio start stop delete permission and web fallback', () async {
    resetSafetyMockForProcess();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    await store.load();
    final recorder = TestSafetyRecorder();
    final audio = SafetyAudioService(recorder: recorder, store: store);
    await expectLater(
      audio.start(),
      throwsA(
        isA<SafetyAudioException>().having((e) => e.code, 'code', 'MIC_DENIED'),
      ),
    );
    expect(recorder.permissionRequests, 1);
    expect(recorder.starts, 0);
    recorder.permissionGranted = true;
    final rec = await audio.start(rideId: 'ride_a');
    expect(audio.isRecording, isTrue);
    expect(rec.localPath, isNull);
    expect(recorder.starts, 1);
    final stopped = await audio.stop();
    expect(stopped.endedAt, isNotNull);
    expect(stopped.localPath, '/device/safety/recording.m4a');
    expect(recorder.stops, 1);
    await audio.delete(stopped);
    expect(recorder.deletedPaths, ['/device/safety/recording.m4a']);

    recorder.capturedPath = null;
    await audio.start(rideId: 'ride_b');
    await expectLater(
      audio.stop(),
      throwsA(
        isA<SafetyAudioException>().having((e) => e.code, 'code', 'NO_AUDIO'),
      ),
    );
    expect(audio.isRecording, isFalse);

    final unsupported = SafetyAudioService(
      recorder: recorder,
      store: store,
      supported: false,
    );
    await expectLater(
      unsupported.start(),
      throwsA(isA<SafetyAudioException>()),
    );
  });

  // rider-r4-27: a double tap on Record ran two overlapping start() calls;
  // both passed isRecording because _active is set only after the awaits.
  test('an overlapping audio start is refused, not a second take', () async {
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    await store.load();
    final recorder = TestSafetyRecorder()..permissionGranted = true;
    final audio = SafetyAudioService(recorder: recorder, store: store);
    final first = audio.start(rideId: 'ride_a');
    await expectLater(
      audio.start(rideId: 'ride_a'),
      throwsA(
        isA<SafetyAudioException>().having(
          (e) => e.code,
          'code',
          'ALREADY_RECORDING',
        ),
      ),
    );
    await first;
    expect(recorder.starts, 1);
    expect(audio.isRecording, isTrue);
  });

  testWidgets('Safety Kit reports denied microphone access honestly', (
    tester,
  ) async {
    _withAudioOption();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final recorder = TestSafetyRecorder();
    final controller = SafetyController(
      session: store,
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(
            rideId: 'ride_denied',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.pumpAndSettle();
    expect(
      find.text('Microphone permission is required to record.'),
      findsOneWidget,
    );
    expect(recorder.permissionRequests, 1);
    expect(recorder.starts, 0);
  });

  test('optimistic write rolls back on simulated server failure', () async {
    resetSafetyMockForProcess();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    await store.load();
    expect(store.preferences.pinRequired, isFalse);
    store.failNextWrite = true;
    await expectLater(
      store.patchPreferences(store.preferences.copyWith(pinRequired: true)),
      throwsA(isA<SafetyException>()),
    );
    expect(store.preferences.pinRequired, isFalse);
  });

  test('rotate PIN idempotency key returns same mock payload', () async {
    resetSafetyMockForProcess();
    final client = InProcessMockClient();
    final api = ApiClient(client: client);
    final first = await api.post(
      '/api/v1/safety/pin/rotate',
      idempotencyKey: 'safety-pin-same',
    );
    final second = await api.post(
      '/api/v1/safety/pin/rotate',
      idempotencyKey: 'safety-pin-same',
    );
    expect(first['pin']['pinId'], second['pin']['pinId']);
  });

  test('malformed safety DTOs do not throw', () {
    expect(
      SafetyPreferences.fromJson({'tripShareMode': 1}).tripShareMode,
      TripShareMode.manual,
    );
    expect(
      RideCheckEvent.fromJson({}).type,
      RideCheckEventType.manualSafetyCheck,
    );
    expect(EmergencyContact.fromJson({}).name, '');
  });

  testWidgets('Safety Kit finishes closing before Trip Share page opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showRideSafetyKit(context, rideId: 'ride_handoff_share'),
              child: const Text('Open Safety Kit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Safety Kit'));
    await tester.pumpAndSettle();
    expect(find.text('Safety tools'), findsOneWidget);

    await tester.tap(find.text('Share trip'));
    await tester.pumpAndSettle();

    expect(find.text('Share trip status'), findsOneWidget);
    expect(find.text('Trip sharing'), findsOneWidget);
    expect(find.text('Safety tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Safety Kit share action creates an active share for the ride', (
    tester,
  ) async {
    final session = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final ctl = SafetyController(session: session);
    await ctl.load();
    await ctl.addContact(
      name: 'Trusted contact',
      phone: '0701234567',
      shareTrips: true,
    );
    await ctl.setTripShare(enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(
            rideId: 'ride_share_action',
            controller: ctl,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share trip'));
    await tester.pumpAndSettle();

    final share = await session.getShare('ride_share_action');
    expect(share, isNotNull);
    expect(share!.isActive, isTrue);
    expect(share.contactIds, contains(ctl.contacts.single.id));
    expect(
      find.text('Trip sharing started for 1 trusted contact.'),
      findsOneWidget,
    );
  });

  testWidgets('Safety Kit finishes closing before Safety Hub opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showRideSafetyKit(context, rideId: 'ride_handoff_hub'),
              child: const Text('Open Safety Kit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Safety Kit'));
    await tester.pumpAndSettle();
    expect(find.text('Safety tools'), findsOneWidget);

    await tester.tap(find.text('Safety preferences'));
    await tester.pumpAndSettle();

    expect(find.text('PIN verification'), findsOneWidget);
    expect(find.text('Emergency contacts'), findsOneWidget);
    expect(find.text('Safety tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
