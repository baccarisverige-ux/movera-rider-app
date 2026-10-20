import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_trip_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rideId = 'ride_rc';

/// Records every request the app sends to the in-process mock.
class _SpyClient extends InProcessMockClient {
  final requests = <({String method, String path, String body})>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add((
      method: request.method,
      path: request.url.path,
      body: request is http.Request ? request.body : '',
    ));
    return super.send(request);
  }
}

class _Recorder implements SafetyRecorder {
  _Recorder({this.supported = true});

  @override
  final bool supported;
  bool permissionGranted = true;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> requestPermission() async => permissionGranted;
  @override
  Future<void> start(String recordingId) async => starts++;
  @override
  Future<String?> stop() async {
    stops++;
    return '/device/safety_recordings/ride_check.m4a';
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {}
}

late _SpyClient _client;
late SafetyStore _store;
late SafetyController _safety;
RideCheckController? _rideCheckOrNull;
RideCheckController get _rideCheck => _rideCheckOrNull!;
set _rideCheck(RideCheckController value) => _rideCheckOrNull = value;
late RecordingEmergencyDialer _dialer;
late _Recorder _recorder;

Future<void> _setUpSafety({
  bool recorderSupported = true,
  EmergencyDialer? dialer,
}) async {
  SharedPreferences.setMockInitialValues({});
  resetSafetyMockForProcess();
  SafetyStore.resetShared();
  SafetyRepository.resetShared();
  SafetyController.resetShared();
  _client = _SpyClient();
  _store = SafetyStore(
    local: PreferencesSafetyLocalDataSource(memoryOnly: true),
    remote: ApiSafetyRemoteDataSource(ApiClient(client: _client)),
  );
  _dialer = RecordingEmergencyDialer();
  _recorder = _Recorder(supported: recorderSupported);
  _safety = SafetyController(
    session: _store,
    emergency: EmergencyCallService(dialer: dialer ?? _dialer),
    audio: SafetyAudioService(recorder: _recorder, store: _store),
  );
  await _safety.load();
  _rideCheck = RideCheckController.forSafety(_safety);
  _rideCheck.attachTrip(
    const RideCheckTripContext(
      rideId: _rideId,
      riderName: 'Sara Lind',
      riderPhone: '+46701234567',
      driverId: 'drv_elin',
      driverName: 'Elin',
      driverPlate: 'MVR 204',
      driverVehicle: 'Black Volvo XC40',
      pickup: RideCheckPlace(
        label: 'Odenplan',
        point: GeoPoint(59.3429, 18.0496),
      ),
      destination: RideCheckPlace(
        label: 'Solna centrum',
        point: GeoPoint(59.3600, 18.0000),
      ),
      rideType: 'Movera',
      status: 'tripInProgress',
    ),
    const RideCheckPlan(
      pickup: GeoPoint(59.3429, 18.0496),
      destination: GeoPoint(59.3600, 18.0000),
      destinationLabel: 'Solna centrum',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    _rideCheckOrNull?.dispose();
    _rideCheckOrNull = null;
    RideCheckController.tripMonitoring = false;
  });

  var behindTaps = 0;

  /// A trip screen with a button behind the card, pushed over a root page so
  /// a working back would leave it.
  Future<GlobalKey<NavigatorState>> pumpTrip(WidgetTester tester) async {
    behindTaps = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Center(child: Text('root page'))),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: TextButton(
                    onPressed: () => behindTaps++,
                    child: const Text('Behind the card'),
                  ),
                ),
              ),
              Positioned.fill(
                child: RideCheckLayer(rideId: _rideId, controller: _rideCheck),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return navigator;
  }

  /// Lets the card grow and every queued save finish (the card's dot keeps
  /// pulsing, so pumpAndSettle would never settle).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> openCard(
    WidgetTester tester,
    RideCheckTrigger trigger, {
    RideCheckReason reason = const RideCheckReason(),
  }) async {
    final result = await _rideCheck.open(
      trigger,
      rideId: _rideId,
      reason: reason,
    );
    expect(result, RideCheckOpenResult.shown);
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Finder card() => find.byKey(const ValueKey<String>('ride-check-card'));

  List<Map<String, dynamic>> answerBodies() => [
    for (final request in _client.requests)
      if (request.path == '/api/v1/safety/ridecheck/answers')
        jsonDecode(request.body) as Map<String, dynamic>,
  ];

  testWidgets(
    'RC3 the dark-glass card opens at the top with the rider rows and Solar icons only',
    (tester) async {
      await _setUpSafety();
      await pumpTrip(tester);
      await openCard(
        tester,
        RideCheckTrigger.droppedFar,
        reason: const RideCheckReason(distanceMeters: 1200),
      );

      expect(find.text('RIDE CHECK'), findsOneWidget);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(
        find.text(
          'Your trip ended 1.2 km from Solna centrum',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Call 112'), findsOneWidget);
      expect(find.text("I'm OK"), findsOneWidget);
      expect(
        find.text(
          'Record audio · saved only on this phone',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Or tell us what happened'), findsOneWidget);
      for (final label in const [
        'There was an accident',
        'Someone is hurt or feels ill',
        'I feel unsafe',
        'I was left at the wrong place',
        'The driver asked me to leave the car',
        'The car broke down',
        'Something else',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Your answer is saved to this trip.'), findsOneWidget);

      // At the top with ~10 px margins, over the screen.
      final box = tester.getRect(card());
      expect(box.top, closeTo(10, 0.5));
      expect(box.left, closeTo(10, 0.5));
      expect(box.right, closeTo(380, 0.5));

      // Solar SVGs only: no Material or Cupertino icon in this feature.
      expect(
        find.descendant(of: card(), matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        find.descendant(of: card(), matching: find.byType(SvgPicture)),
        findsAtLeastNWidgets(10),
      );
      // Opening the card never calls anyone.
      expect(_dialer.calls, isEmpty);
    },
  );

  testWidgets(
    'RC5 it cannot be dismissed: no close, back, tap outside or swipe',
    (tester) async {
      await _setUpSafety();
      final navigator = await pumpTrip(tester);
      await openCard(tester, RideCheckTrigger.longStop);

      expect(find.byTooltip('Close'), findsNothing);
      expect(find.byType(CloseButton), findsNothing);
      expect(find.text('Close'), findsNothing);

      // Back does nothing.
      await navigator.currentState!.maybePop();
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(find.text('root page'), findsNothing);

      // Nothing behind it can be tapped.
      await tester.tapAt(tester.getCenter(find.text('Behind the card')));
      await settle(tester);
      expect(behindTaps, 0);

      // No swipe-away, in any direction.
      for (final offset in const [
        Offset(0, -500),
        Offset(400, 0),
        Offset(-400, 0),
      ]) {
        await tester.fling(find.text('RIDE CHECK'), offset, 2400);
        await settle(tester);
      }
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(_rideCheck.session, isNotNull);
      expect(_rideCheck.blocks(_rideId), isTrue);
    },
  );

  testWidgets("I'm OK saves the answer to the trip and closes the card", (
    tester,
  ) async {
    await _setUpSafety();
    await pumpTrip(tester);
    await openCard(
      tester,
      RideCheckTrigger.longStop,
      reason: const RideCheckReason(stoppedMinutes: 4, place: 'Odenplan'),
    );
    expect(
      find.text(
        'Your car has stopped for 4 min · Odenplan',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'ride-check-ok');
    await tester.pump(const Duration(milliseconds: 400));

    expect(_rideCheck.session, isNull);
    expect(find.text('Is everything OK?'), findsNothing);
    expect(_rideCheck.blocks(_rideId), isFalse);

    final mock = safetyMockForProcess();
    expect(mock.rideCheckAlerts, isEmpty, reason: "I'm OK is not an alert");
    final saved = mock.rideCheckAnswers.single;
    expect(saved['final'], isTrue);
    expect((saved['answers'] as List).single['id'], 'ok');
    expect(saved['trigger'], 'long_stop');

    final records = await _safety.rideCheck.records(_rideId);
    expect(records.single.answerSummary, "I'm OK");
    expect(records.single.trigger, RideCheckTrigger.longStop);
    final event = _store.rideCheckEvents.single;
    expect(event.status, RideCheckStatus.resolved);
    // The server was told the check is resolved.
    expect(
      _client.requests.where(
        (r) => r.path.endsWith('/safety-events/${event.eventId}/respond'),
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'RC4 a red row alerts the safety team at once with rider, driver and trip details',
    (tester) async {
      await _setUpSafety();
      await pumpTrip(tester);
      await openCard(tester, RideCheckTrigger.longStop);

      await tapKey(tester, 'ride-check-row-accident');

      // The follow-up screen.
      expect(find.text('RIDE CHECK · ACCIDENT'), findsOneWidget);
      expect(find.text('Is anyone hurt?'), findsOneWidget);
      expect(find.text('Is the car in a safe place?'), findsOneWidget);
      expect(find.text('Is the other person OK?'), findsOneWidget);

      // Alerted before any question was answered.
      final alerts = safetyMockForProcess().rideCheckAlerts.values.toList();
      expect(alerts, hasLength(1));
      final alert = alerts.single;
      expect(alert['status'], 'sent');
      expect(alert['recipients'], ['admin', 'dispatch']);
      expect(alert['rider'], containsPair('name', 'Sara Lind'));
      expect(alert['rider'], containsPair('phone', '+46701234567'));
      expect(alert['driver'], containsPair('plate', 'MVR 204'));
      expect(alert['driver'], containsPair('name', 'Elin'));
      expect((alert['trip'] as Map)['rideId'], _rideId);
      expect(((alert['trip'] as Map)['pickup'] as Map)['label'], 'Odenplan');
      expect(((alert['answers'] as List).single as Map)['id'], 'accident');

      expect(find.text('Movera safety team alerted'), findsOneWidget);
      expect(
        find.text('Trip, driver and rider details were sent.'),
        findsOneWidget,
      );
      expect(_rideCheck.session!.alertState, RideCheckAlertState.sent);
      // Still up: tapping a row is an answer, but the card waits for Done.
      expect(_rideCheck.blocks(_rideId), isTrue);
    },
  );

  testWidgets('RC4 any Yes or Not sure updates the alert; No does not', (
    tester,
  ) async {
    await _setUpSafety();
    await pumpTrip(tester);
    await openCard(tester, RideCheckTrigger.longStop);
    await tapKey(tester, 'ride-check-row-accident');
    Map<String, dynamic> alert() =>
        safetyMockForProcess().rideCheckAlerts.values.single;
    expect(alert()['updates'], 0);
    expect(find.text('Call 112 now'), findsNothing);

    await tapKey(tester, 'ride-check-option-anyone_hurt-yes');
    expect(alert()['updates'], 1);
    expect(alert()['status'], 'updated');
    expect(find.text('Call 112 now'), findsOneWidget);
    expect(
      find.text('If someone is hurt or in danger, call emergency services.'),
      findsOneWidget,
    );

    await tapKey(tester, 'ride-check-option-car_safe_place-no');
    expect(alert()['updates'], 1, reason: 'No is saved with Done, not pushed');

    await tapKey(tester, 'ride-check-option-other_person_ok-notSure');
    expect(alert()['updates'], 2);
    final answers = (alert()['answers'] as List).cast<Map>();
    expect(answers.map((a) => a['id']), [
      'accident',
      'anyone_hurt',
      'car_safe_place',
      'other_person_ok',
    ]);
    expect(answers.last['value'], 'not_sure');

    await tapKey(tester, 'ride-check-done');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_rideCheck.session, isNull);
    final record = (await _safety.rideCheck.records(_rideId)).single;
    expect(record.alerted, isTrue);
    expect(
      record.answerSummary,
      'There was an accident · Is anyone hurt? Yes · '
      'Is the car in a safe place? No · Is the other person OK? Not sure',
    );
  });

  testWidgets('Call 112 opens the phone dialer with 112; Movera never calls', (
    tester,
  ) async {
    await _setUpSafety();
    await pumpTrip(tester);
    await openCard(
      tester,
      RideCheckTrigger.offRoute,
      reason: const RideCheckReason(distanceMeters: 2400),
    );
    expect(
      find.text('Your car is 2.4 km off the route', findRichText: true),
      findsOneWidget,
    );
    expect(_dialer.calls, isEmpty);

    await tapKey(tester, 'ride-check-call-112');
    expect(_dialer.calls, ['112']);
    expect(_safety.emergency.explicitCallCount, 1);
    // The rider called: the safety team is alerted and the card may close.
    expect(find.text('Movera safety team alerted'), findsOneWidget);
    expect(safetyMockForProcess().rideCheckAlerts, hasLength(1));

    await tapKey(tester, 'ride-check-done');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_rideCheck.session, isNull);
    expect(_dialer.calls, ['112'], reason: 'nothing dials on its own');
    expect(
      (await _safety.rideCheck.records(_rideId)).single.answerSummary,
      'Called 112',
    );
  });

  testWidgets('Call 112 goes to the system dialer as tel:112', (tester) async {
    final launched = <Uri>[];
    await _setUpSafety(
      dialer: SystemEmergencyDialer(
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await pumpTrip(tester);
    await openCard(tester, RideCheckTrigger.longStop);
    await tapKey(tester, 'ride-check-call-112');
    expect(launched.single.toString(), 'tel:112');
  });

  testWidgets('a possible crash opens at once with Call 112 on top', (
    tester,
  ) async {
    await _setUpSafety();
    await pumpTrip(tester);
    await _rideCheck.open(RideCheckTrigger.possibleCrash, rideId: _rideId);
    await tester.pump();
    await tester.pump();
    // Already full size: no island phase.
    expect(find.text('Is everything OK?'), findsOneWidget);
    expect(
      find.text('We noticed a very hard stop', findRichText: true),
      findsOneWidget,
    );
    final callNow = find.byKey(
      const ValueKey<String>('ride-check-call-112-now'),
    );
    final ok = find.byKey(const ValueKey<String>('ride-check-ok'));
    expect(tester.getTopLeft(callNow).dy, lessThan(tester.getTopLeft(ok).dy));
    expect(find.text('I asked the driver to stop'), findsOneWidget);
    await tester.tap(callNow);
    await settle(tester);
    expect(_dialer.calls, ['112']);
  });

  testWidgets(
    'RC5 Record audio stays on this phone and is never sent to Movera',
    (tester) async {
      await _setUpSafety();
      await pumpTrip(tester);
      await openCard(tester, RideCheckTrigger.longStop);

      await tapKey(tester, 'ride-check-record');
      expect(_recorder.starts, 1);
      expect(_rideCheck.recording, isTrue);
      expect(
        find.textContaining('Recording 0:', findRichText: true),
        findsOneWidget,
      );

      await tapKey(tester, 'ride-check-record');
      expect(_recorder.stops, 1);
      expect(find.text('Recording saved on this phone only.'), findsOneWidget);

      // A second recording is stopped and kept when the card closes.
      await tapKey(tester, 'ride-check-record');
      expect(_recorder.starts, 2);
      await tapKey(tester, 'ride-check-ok');
      await tester.pump(const Duration(milliseconds: 400));
      expect(_recorder.stops, 2);
      expect(_rideCheck.recording, isFalse);

      // Nothing about the recordings reached Movera: no audio route was
      // called, the mock holds no recording, and the answers carry none.
      expect(
        _client.requests.where((r) => r.path.contains('safety-audio')),
        isEmpty,
      );
      expect(safetyMockForProcess().recordings, isEmpty);
      final bodies = answerBodies();
      expect(bodies, isNotEmpty);
      for (final body in bodies) {
        final text = jsonEncode(body);
        expect(text, isNot(contains('m4a')));
        expect(text, isNot(contains('safety_recordings')));
        expect(text.toLowerCase(), isNot(contains('audio')));
        expect(text.toLowerCase(), isNot(contains('recording')));
      }
    },
  );

  testWidgets('Record audio says so where the phone cannot record', (
    tester,
  ) async {
    await _setUpSafety(recorderSupported: false);
    await pumpTrip(tester);
    await openCard(tester, RideCheckTrigger.longStop);
    await tapKey(tester, 'ride-check-record');
    expect(
      find.text("Recording isn't available on this device."),
      findsOneWidget,
    );
    expect(_rideCheck.session, isNotNull);
  });

  testWidgets(
    'rows without questions say the answer is saved; Something else takes a note',
    (tester) async {
      await _setUpSafety();
      await pumpTrip(tester);
      await openCard(tester, RideCheckTrigger.offRoute);
      await tapKey(tester, 'ride-check-row-asked_for_route');
      expect(find.text('RIDE CHECK · ROUTE'), findsOneWidget);
      expect(find.text('Thanks, this is saved to the trip.'), findsOneWidget);
      expect(safetyMockForProcess().rideCheckAlerts, isEmpty);
      await tapKey(tester, 'ride-check-done');
      await tester.pump(const Duration(milliseconds: 400));

      await openCard(tester, RideCheckTrigger.longStop);
      await tapKey(tester, 'ride-check-row-something_else');
      expect(find.text('What happened?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('ride-check-note')),
        'Driver took a call',
      );
      await tapKey(tester, 'ride-check-done');
      await tester.pump(const Duration(milliseconds: 400));
      final records = await _safety.rideCheck.records(_rideId);
      expect(
        records.map((r) => r.answerSummary),
        containsAll(<String>[
          'I asked for this route',
          'Something else · “Driver took a call”',
        ]),
      );
    },
  );

  testWidgets(
    'an unanswered card comes back when the trip screen opens again',
    (tester) async {
      await _setUpSafety();
      await _rideCheck.open(RideCheckTrigger.longStop, rideId: _rideId);
      await _rideCheck.settle();
      // The app restarts: a fresh controller over the same saved state.
      _rideCheck.dispose();
      _rideCheck = RideCheckController.forSafety(_safety);
      await pumpTrip(tester);
      await settle(tester);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(_rideCheck.session?.trigger, RideCheckTrigger.longStop);
    },
  );

  testWidgets(
    'a server RideCheck alert opens the card and I\'m OK sends resolution',
    (tester) async {
      await _setUpSafety();
      final alert = await _safety.rideCheck.unexpectedStop(rideId: _rideId);
      await pumpTrip(tester);
      await settle(tester);
      expect(find.text('Is everything OK?'), findsOneWidget);
      await tapKey(tester, 'ride-check-ok');
      final confirmed = await _safety.rideCheck.refresh(_rideId);
      expect(confirmed.single.eventId, alert.eventId);
      expect(confirmed.single.status, RideCheckStatus.resolved);
    },
  );

  group('RC5 ride details', () {
    Future<void> answerOk(WidgetTester tester) async {
      await pumpTrip(tester);
      await openCard(tester, RideCheckTrigger.longStop);
      await tapKey(tester, 'ride-check-ok');
      await tester.pump(const Duration(milliseconds: 400));
    }

    String timeOf(RideCheckRecord record) {
      final local = record.shownAt.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }

    testWidgets(
      'the trip details show a Ride check entry with time, trigger and answer',
      (tester) async {
        await _setUpSafety();
        await answerOk(tester);
        final record = (await _safety.rideCheck.records(_rideId)).single;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RideCheckTripEntry(
                rideId: _rideId,
                service: _safety.rideCheck,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('ride-check-trip-entry')),
          findsOneWidget,
        );
        expect(find.text('Ride check'), findsOneWidget);
        expect(find.text('${timeOf(record)} · Long stop'), findsOneWidget);
        expect(find.text("I'm OK"), findsOneWidget);
      },
    );

    testWidgets('a trip with no Ride check shows no entry', (tester) async {
      await _setUpSafety();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideCheckTripEntry(
              rideId: 'other_ride',
              service: _safety.rideCheck,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ride check'), findsNothing);
    });

    testWidgets('a completed ride in History shows its Ride check', (
      tester,
    ) async {
      await _setUpSafety();
      await answerOk(tester);
      SafetyController.sharedForTest = _safety;
      addTearDown(() => SafetyController.sharedForTest = null);
      final ride = Reservation(
        reservationId: 'ondemand-$_rideId',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        scheduledPickupAt: DateTime.now(),
        pickup: const ReservationPlace(label: 'Odenplan'),
        destination: const ReservationPlace(label: 'Solna centrum'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 259,
        paymentMethod: 'Apple Pay',
        status: ReservationStatus.completed,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RideHistory(
            reservations: ReservationController(
              store: LocalReservationRepository(
                storage: MemoryReservationStorage(),
              ),
            ),
            onDemandReader: () async => [ride],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Solna centrum').first);
      await tester.pumpAndSettle();
      expect(find.text('Completed ride'), findsOneWidget);
      expect(find.text('Ride check'), findsOneWidget);
      expect(find.textContaining('Long stop'), findsOneWidget);
      expect(find.text("I'm OK"), findsOneWidget);
    });
  });

  testWidgets('a scheduled ride\'s details show its Ride check', (
    tester,
  ) async {
    await _setUpSafety();
    SafetyController.sharedForTest = _safety;
    RideCheckController.sharedForTest = _rideCheck;
    addTearDown(() {
      RideCheckController.sharedForTest = null;
      SafetyController.sharedForTest = null;
    });
    final reservations = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_rc',
      ),
    );
    await reservations.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.now().add(const Duration(days: 1)),
        pickup: const ReservationPlace(
          label: 'Odenplan',
          lat: 59.34,
          lng: 18.05,
        ),
        destination: const ReservationPlace(
          label: 'Solna centrum',
          lat: 59.36,
          lng: 18.0,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 259,
        paymentMethod: 'Apple Pay',
      ),
    );
    // The scheduled trip ran under its reservation id.
    await _rideCheck.open(
      RideCheckTrigger.offRoute,
      rideId: 'rsv_rc',
      reason: const RideCheckReason(longerPercent: 60),
    );
    _rideCheck.chooseRow(RideCheckRowId.askedRoute);
    _rideCheck.done();
    await _rideCheck.settle();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(
          reservationId: 'rsv_rc',
          controller: reservations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ride check'), 200);
    expect(find.text('Ride check'), findsOneWidget);
    expect(find.textContaining('Off the route'), findsOneWidget);
    expect(find.text('I asked for this route'), findsOneWidget);
  });

  testWidgets(
    'the card fits a small phone and scrolls instead of overflowing',
    (tester) async {
      await _setUpSafety();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideCheckLayer(rideId: _rideId, controller: _rideCheck),
          ),
        ),
      );
      await openCard(
        tester,
        RideCheckTrigger.droppedFar,
        reason: const RideCheckReason(distanceMeters: 1200),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(card()).bottom, lessThanOrEqualTo(568));
      await tapKey(tester, 'ride-check-row-something_else');
      expect(tester.takeException(), isNull);
    },
  );

  test('records read back from the saved event', () {
    final event = RideCheckEvent(
      eventId: 'rc_x',
      rideId: 'r',
      type: RideCheckEventType.droppedFar,
      at: DateTime.utc(2026, 10, 15, 13, 5),
      payload: {
        'kind': rideCheckEventKind,
        'trigger': 'dropped_far',
        'answers': [
          RideCheckAnswer.ok(DateTime.utc(2026, 10, 15, 13, 6)).toJson(),
        ],
      },
    );
    final record = RideCheckRecord.fromEvent(event)!;
    expect(record.trigger, RideCheckTrigger.droppedFar);
    expect(record.answerSummary, "I'm OK");
    expect(
      RideCheckRecord.fromEvent(
        RideCheckEvent(
          eventId: 'sos',
          rideId: 'r',
          type: RideCheckEventType.manualSafetyCheck,
          at: DateTime.utc(2026),
          payload: const {'kind': 'sos'},
        ),
      ),
      isNull,
    );
  });

  test('the monitor plan is built from the trip', () {
    const plan = RideCheckPlan(
      pickup: GeoPoint(1, 1),
      destination: GeoPoint(2, 2),
      stops: [GeoPoint(1.5, 1.5)],
    );
    expect(plan.plannedStops, hasLength(3));
  });
}
