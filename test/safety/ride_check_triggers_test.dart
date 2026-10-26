import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pickup = GeoPoint(59.3293, 18.0686);
const _destination = GeoPoint(59.3600, 18.0000);
const _plan = RideCheckPlan(
  pickup: _pickup,
  destination: _destination,
  destinationLabel: 'Solna centrum',
);

/// A point [meters] north of [from].
GeoPoint _north(GeoPoint from, double meters) =>
    GeoPoint(from.latitude + meters / 111320, from.longitude);

RideCheckMonitor _monitor({
  RideCheckTriggerSettings settings = const RideCheckTriggerSettings(),
}) => RideCheckMonitor(settings: settings, plan: _plan);

final _t0 = DateTime.utc(2026, 10, 15, 14, 0);

void main() {
  group('RC1 defaults and settings', () {
    test('the app defaults are 3 km, 2 min, 2 km / 50% and crash on', () {
      const settings = RideCheckTriggerSettings();
      expect(settings.finishFarFromDropoffKm, 3);
      expect(settings.longStopMinutes, 2);
      expect(settings.offRouteKm, 2);
      expect(settings.longerThanExpectedPercent, 50);
      for (final trigger in RideCheckTrigger.values) {
        expect(settings.isOn(trigger), isTrue, reason: trigger.name);
      }
      expect(const RideCheckPolicy().enabled, isTrue);
    });

    test('admin numbers and on/off are read from the policy JSON', () {
      final policy = RideCheckPolicy.fromJson({
        'enabled': true,
        'triggers': {
          'droppedFar': {'enabled': false, 'km': 4.5},
          'longStop': {'enabled': true, 'minutes': 6},
          'offRoute': {'enabled': true, 'km': 3.5, 'longerPercent': 70},
          'possibleCrash': {'enabled': false},
        },
      });
      final t = policy.triggers;
      expect(t.droppedFarEnabled, isFalse);
      expect(t.finishFarFromDropoffKm, 4.5);
      expect(t.longStopMinutes, 6);
      expect(t.offRouteKm, 3.5);
      expect(t.longerThanExpectedPercent, 70);
      expect(policy.allows(RideCheckTrigger.droppedFar), isFalse);
      expect(policy.allows(RideCheckTrigger.possibleCrash), isFalse);
      expect(policy.allows(RideCheckTrigger.longStop), isTrue);
      // A round trip keeps them.
      final again = RideCheckPolicy.fromJson(policy.toJson());
      expect(again.triggers.toJson(), t.toJson());
    });

    test('bad admin numbers fall back to the app defaults', () {
      final t = RideCheckTriggerSettings.fromJson({
        'droppedFar': {'km': -1},
        'longStop': {'minutes': 'four'},
        'offRoute': {'km': 0},
      });
      expect(t.finishFarFromDropoffKm, 3);
      expect(t.longStopMinutes, 2);
      expect(t.offRouteKm, 2);
    });

    test(
      'the mock API serves the trigger defaults and the rider cannot change them',
      () async {
        resetSafetyMockForProcess();
        final api = ApiClient(client: InProcessMockClient());
        final remote = ApiSafetyRemoteDataSource(api);
        final policy = await remote.getRideCheck();
        expect(policy.enabled, isTrue);
        expect(
          policy.triggers.toJson(),
          const RideCheckTriggerSettings().toJson(),
        );

        final patched = await remote.patchRideCheck(
          policy.copyWith(
            enabled: false,
            triggers: const RideCheckTriggerSettings(droppedFarEnabled: false),
          ),
        );
        expect(patched.enabled, isFalse);
        expect(patched.triggers.droppedFarEnabled, isTrue);
      },
    );

    test('QA and API names map to triggers', () {
      expect(parseRideCheckTrigger('droppedFar'), RideCheckTrigger.droppedFar);
      expect(parseRideCheckTrigger('long_stop'), RideCheckTrigger.longStop);
      expect(
        parseRideCheckTrigger('unexpectedStop'),
        RideCheckTrigger.longStop,
      );
      expect(
        parseRideCheckTrigger('routeDeviation'),
        RideCheckTrigger.offRoute,
      );
      expect(
        parseRideCheckTrigger('possibleCrash'),
        RideCheckTrigger.possibleCrash,
      );
      expect(parseRideCheckTrigger('nope'), isNull);
    });
  });

  group('R8-6 trigger decision (admin X km / Y min)', () {
    test('finished far: over X km fires, at or under X km does not', () {
      const t = RideCheckTriggerSettings();
      expect(t.finishedFarFromDropoff(3001), isTrue);
      expect(t.finishedFarFromDropoff(3000), isFalse);
      expect(t.finishedFarFromDropoff(2999), isFalse);
      const five = RideCheckTriggerSettings(finishFarFromDropoffKm: 5);
      expect(five.finishedFarFromDropoff(4000), isFalse);
      expect(five.finishedFarFromDropoff(5200), isTrue);
    });

    test('long stop: over Y min fires, at or under Y min does not', () {
      const t = RideCheckTriggerSettings();
      expect(t.isLongStop(const Duration(minutes: 2, seconds: 1)), isTrue);
      expect(t.isLongStop(const Duration(minutes: 2)), isFalse);
      expect(t.isLongStop(const Duration(minutes: 1, seconds: 59)), isFalse);
      const ten = RideCheckTriggerSettings(longStopMinutes: 10);
      expect(ten.isLongStop(const Duration(minutes: 8)), isFalse);
      expect(ten.isLongStop(const Duration(minutes: 11)), isTrue);
    });

    test('reads admin finishFarFromDropoffKm / longStopMinutes', () {
      final t = RideCheckTriggerSettings.fromJson({
        'finishFarFromDropoffKm': 5,
        'longStopMinutes': 10,
        'droppedFar': {'enabled': true, 'km': 2},
        'longStop': {'enabled': true, 'minutes': 3},
      });
      expect(t.finishFarFromDropoffKm, 5);
      expect(t.longStopMinutes, 10);
      // An older server's metres still read.
      final legacy = RideCheckTriggerSettings.fromJson({
        'droppedFar': {'meters': 800},
      });
      expect(legacy.finishFarFromDropoffKm, 0.8);
      // The mock admin config serves the defaults.
      final mock = RideCheckTriggerSettings.fromJson(
        SafetyMockApi.defaultRideCheckTriggers(),
      );
      expect(mock.finishFarFromDropoffKm, 3);
      expect(mock.longStopMinutes, 2);
    });
  });

  group('RC1 dropped far away', () {
    test('fires when the driver finishes more than 3 km from the drop-off', () {
      final monitor = _monitor();
      expect(monitor.tripEnded(_north(_destination, 2900)), isNull);
      final hit = _monitor().tripEnded(_north(_destination, 3600));
      expect(hit?.trigger, RideCheckTrigger.droppedFar);
      expect(hit!.reason.distanceMeters, closeTo(3600, 40));
      expect(hit.reason.destinationLabel, 'Solna centrum');
    });

    test('uses the admin distance and stays quiet when off', () {
      final far = _north(_destination, 4000);
      expect(
        _monitor(
          settings: const RideCheckTriggerSettings(finishFarFromDropoffKm: 5),
        ).tripEnded(far),
        isNull,
      );
      expect(
        _monitor(
          settings: const RideCheckTriggerSettings(droppedFarEnabled: false),
        ).tripEnded(_north(_destination, 8000)),
        isNull,
      );
    });
  });

  group('RC1 long stop', () {
    final stopAt = _north(_pickup, 2000);

    List<RideCheckSample> still(
      GeoPoint at,
      Duration length, {
      bool traffic = false,
    }) => [
      for (var s = 0; s <= length.inSeconds; s += 3)
        RideCheckSample(
          point: at,
          at: _t0.add(Duration(seconds: s)),
          inTraffic: traffic,
        ),
    ];

    RideCheckDetection? feed(
      RideCheckMonitor monitor,
      List<RideCheckSample> samples,
    ) {
      RideCheckDetection? hit;
      for (final sample in samples) {
        hit ??= monitor.addSample(sample);
      }
      return hit;
    }

    test('fires after more than 2 min without moving mid-trip', () {
      final monitor = _monitor();
      expect(feed(monitor, still(stopAt, const Duration(minutes: 2))), isNull);
      final hit = monitor.addSample(
        RideCheckSample(
          point: stopAt,
          at: _t0.add(const Duration(minutes: 2, seconds: 3)),
        ),
      );
      expect(hit?.trigger, RideCheckTrigger.longStop);
      expect(hit!.reason.stoppedMinutes, 2);
      // Once per trip.
      expect(
        monitor.addSample(
          RideCheckSample(
            point: stopAt,
            at: _t0.add(const Duration(minutes: 9)),
          ),
        ),
        isNull,
      );
    });

    test('fires on the clock when no new fix comes in while stopped', () {
      final monitor = _monitor();
      expect(monitor.checkStill(_t0), isNull);
      expect(
        monitor.addSample(RideCheckSample(point: stopAt, at: _t0)),
        isNull,
      );
      expect(monitor.checkStill(_t0.add(const Duration(minutes: 2))), isNull);
      final hit = monitor.checkStill(
        _t0.add(const Duration(minutes: 2, seconds: 15)),
      );
      expect(hit?.trigger, RideCheckTrigger.longStop);
      expect(hit!.reason.stoppedMinutes, 2);
      // Once per trip.
      expect(monitor.checkStill(_t0.add(const Duration(minutes: 5))), isNull);

      // Not at a planned stop, not in traffic.
      final atPickup = _monitor()
        ..addSample(RideCheckSample(point: _pickup, at: _t0));
      expect(atPickup.checkStill(_t0.add(const Duration(minutes: 5))), isNull);
      final inTraffic = _monitor()
        ..addSample(RideCheckSample(point: stopAt, at: _t0, inTraffic: true));
      expect(inTraffic.checkStill(_t0.add(const Duration(minutes: 5))), isNull);
    });

    test('not at a planned stop, not in traffic, not when off', () {
      expect(
        feed(_monitor(), still(_pickup, const Duration(minutes: 6))),
        isNull,
      );
      expect(
        feed(
          _monitor(),
          still(_north(_destination, 80), const Duration(minutes: 6)),
        ),
        isNull,
      );
      expect(
        feed(
          _monitor(),
          still(stopAt, const Duration(minutes: 6), traffic: true),
        ),
        isNull,
      );
      expect(
        feed(
          _monitor(
            settings: const RideCheckTriggerSettings(longStopEnabled: false),
          ),
          still(stopAt, const Duration(minutes: 6)),
        ),
        isNull,
      );
      expect(
        feed(
          _monitor(
            settings: const RideCheckTriggerSettings(longStopMinutes: 8),
          ),
          still(stopAt, const Duration(minutes: 6)),
        ),
        isNull,
      );
    });

    test('a car that keeps moving never fires', () {
      final monitor = _monitor();
      RideCheckDetection? hit;
      for (var s = 0; s < 600; s += 3) {
        hit ??= monitor.addSample(
          RideCheckSample(
            point: _north(_pickup, s * 8.0),
            at: _t0.add(Duration(seconds: s)),
          ),
        );
      }
      expect(hit, isNull);
    });
  });

  group('RC1 off the route', () {
    final route = [_pickup, _north(_pickup, 5000)];

    test('fires more than 2 km off the road route', () {
      final monitor = _monitor()..setPlannedRoute(route);
      final near = GeoPoint(_pickup.latitude + 0.02, _pickup.longitude + 0.03);
      expect(
        monitor.addSample(
          RideCheckSample(point: near, at: _t0, etaSeconds: 1200),
        ),
        isNull,
      );
      final far = GeoPoint(_pickup.latitude + 0.02, _pickup.longitude + 0.045);
      // 850 m in 30 s: driving (rider-r3-4: in 3 s it is a GPS jump).
      final hit = monitor.addSample(
        RideCheckSample(point: far, at: _t0.add(const Duration(seconds: 30))),
      );
      expect(hit?.trigger, RideCheckTrigger.offRoute);
      expect(hit!.reason.distanceMeters, greaterThan(2000));
    });

    test('without a road route only the time rule applies', () {
      final monitor = _monitor();
      final far = GeoPoint(_pickup.latitude, _pickup.longitude + 0.2);
      expect(
        monitor.addSample(
          RideCheckSample(point: far, at: _t0, etaSeconds: 600),
        ),
        isNull,
      );
    });

    test('fires when the trip takes 50% longer than expected', () {
      final monitor = _monitor();
      var lat = _pickup.latitude;
      RideCheckDetection? hit;
      // Expected 10 min; drive on for 16 min.
      for (var s = 0; s <= 16 * 60; s += 30) {
        lat += 0.001;
        hit ??= monitor.addSample(
          RideCheckSample(
            point: GeoPoint(lat, _pickup.longitude),
            at: _t0.add(Duration(seconds: s)),
            etaSeconds: s == 0 ? 600 : null,
          ),
        );
        if (s < 15 * 60) expect(hit, isNull, reason: 'at $s s');
      }
      expect(hit?.trigger, RideCheckTrigger.offRoute);
      expect(hit!.reason.longerPercent, greaterThanOrEqualTo(50));
    });

    test(
      'a short trip a few minutes late does not fire, and off means off',
      () {
        final monitor = _monitor();
        var hit = monitor.addSample(
          RideCheckSample(point: _pickup, at: _t0, etaSeconds: 120),
        );
        hit ??= monitor.addSample(
          RideCheckSample(
            point: _north(_pickup, 500),
            at: _t0.add(const Duration(minutes: 4)),
          ),
        );
        expect(hit, isNull);

        final off = _monitor(
          settings: const RideCheckTriggerSettings(offRouteEnabled: false),
        )..setPlannedRoute(route);
        expect(
          off.addSample(
            RideCheckSample(
              point: GeoPoint(_pickup.latitude, _pickup.longitude + 0.2),
              at: _t0,
              etaSeconds: 60,
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('RC1 possible crash', () {
    RideCheckDetection? drive(
      RideCheckMonitor monitor,
      List<double> metersPerStep,
    ) {
      var at = _pickup;
      RideCheckDetection? hit;
      for (final (i, step) in metersPerStep.indexed) {
        at = _north(at, step);
        hit ??= monitor.addSample(
          RideCheckSample(
            point: at,
            at: _t0.add(Duration(seconds: 3 * i)),
          ),
        );
      }
      return hit;
    }

    test('a very hard stop from 50 km/h fires', () {
      // ~14 m/s, then standing still within one fix.
      final hit = drive(_monitor(), [0, 42, 42, 42, 1, 0]);
      expect(hit?.trigger, RideCheckTrigger.possibleCrash);
    });

    test('a normal stop, a GPS jump or crash off does not fire', () {
      expect(drive(_monitor(), [0, 42, 30, 18, 8, 2, 0]), isNull);
      expect(drive(_monitor(), [0, 900, 0, 0]), isNull);
      expect(
        drive(
          _monitor(
            settings: const RideCheckTriggerSettings(
              possibleCrashEnabled: false,
            ),
          ),
          [0, 42, 42, 42, 1, 0],
        ),
        isNull,
      );
    });
  });

  group('RC3 rider rows', () {
    List<String> labels(RideCheckTrigger trigger) => [
      for (final row in rideCheckRowsFor(trigger)) row.label,
    ];

    test('the three red rows come first for every trigger', () {
      for (final trigger in RideCheckTrigger.values) {
        final rows = rideCheckRowsFor(trigger);
        expect(rows.take(3).every((row) => row.red), isTrue);
        expect(rows.skip(3).any((row) => row.red), isFalse);
        expect(labels(trigger).take(3), [
          'There was an accident',
          'Someone is hurt or feels ill',
          'I feel unsafe',
        ]);
      }
    });

    test('each trigger has its own rows', () {
      expect(labels(RideCheckTrigger.droppedFar).skip(3), [
        'I was left at the wrong place',
        'The driver asked me to leave the car',
        'The car broke down',
        'Something else',
      ]);
      expect(labels(RideCheckTrigger.longStop).skip(3), [
        'I asked the driver to stop',
        'The car broke down',
        'Something else',
      ]);
      expect(labels(RideCheckTrigger.offRoute).skip(3), [
        'I asked for this route',
        'The car broke down',
        'Something else',
      ]);
      expect(
        labels(RideCheckTrigger.possibleCrash),
        labels(RideCheckTrigger.longStop),
      );
    });

    test('follow-ups ask what the spec asks', () {
      final accident = rideCheckRow(RideCheckRowId.accident).followUp;
      expect(
        [for (final q in accident.questions) q.text],
        [
          'Is anyone hurt?',
          'Is the car in a safe place?',
          'Is the other person OK?',
        ],
      );
      final hurt = rideCheckRow(RideCheckRowId.hurt).followUp.questions.single;
      expect(
        [for (final o in hurt.options) o.label],
        ['Me', 'The driver', 'Someone else'],
      );
      expect(
        rideCheckRow(RideCheckRowId.unsafe).followUp.questions.single.text,
        'Are you in danger right now?',
      );
      expect(
        rideCheckRow(
          RideCheckRowId.carBrokeDown,
        ).followUp.questions.single.text,
        'Can you continue the trip?',
      );
      expect(
        rideCheckRow(RideCheckRowId.somethingElse).followUp.asksForNote,
        isTrue,
      );
      expect(
        rideCheckRow(RideCheckRowId.wrongPlace).followUp.thanksOnly,
        isTrue,
      );
    });
  });

  group('RC4 answers endpoint', () {
    setUp(resetSafetyMockForProcess);

    RideCheckSubmission submission({
      required bool alert,
      String? alertId,
      List<RideCheckAnswer> answers = const [],
    }) => RideCheckSubmission(
      checkId: 'rc_1',
      trigger: RideCheckTrigger.longStop,
      shownAt: _t0,
      answers: answers,
      alert: alert,
      alertId: alertId,
      reason: const RideCheckReason(stoppedMinutes: 4),
      context: const RideCheckTripContext(
        rideId: 'ride_1',
        riderName: 'Sara Lind',
        riderPhone: '+46701234567',
        driverId: 'drv_1',
        driverName: 'Elin',
        driverPlate: 'MVR 204',
        driverVehicle: 'Black Volvo XC40',
        pickup: RideCheckPlace(label: 'Odenplan', point: _pickup),
        destination: RideCheckPlace(
          label: 'Solna centrum',
          point: _destination,
        ),
      ),
    );

    test(
      'a red row sends the alert with rider, driver and trip; Yes updates it',
      () async {
        final remote = ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        );
        final accident = rideCheckRow(RideCheckRowId.accident);
        final first = await remote.postRideCheckAnswers(
          submission(
            alert: true,
            answers: [RideCheckAnswer.row(accident, _t0)],
          ),
        );
        expect(first.alerted, isTrue);
        expect(first.alertStatus, 'sent');
        expect(first.recipients, ['admin', 'dispatch']);
        final mock = safetyMockForProcess();
        final alert = mock.rideCheckAlerts[first.alertId]!;
        expect(alert['rider'], {
          'id': 'rider-local',
          'name': 'Sara Lind',
          'phone': '+46701234567',
        });
        expect(alert['driver'], {
          'id': 'drv_1',
          'name': 'Elin',
          'plate': 'MVR 204',
          'vehicle': 'Black Volvo XC40',
        });
        expect((alert['trip'] as Map)['rideId'], 'ride_1');
        expect(
          ((alert['trip'] as Map)['destination'] as Map)['label'],
          'Solna centrum',
        );

        final hurt = accident.followUp.questions.first;
        final update = await remote.postRideCheckAnswers(
          submission(
            alert: true,
            alertId: first.alertId,
            answers: [
              RideCheckAnswer.row(accident, _t0),
              RideCheckAnswer.question(hurt, hurt.options.first, _t0),
            ],
          ),
        );
        expect(update.alertId, first.alertId);
        expect(update.alertStatus, 'updated');
        expect(mock.rideCheckAlerts, hasLength(1));
        expect(mock.rideCheckAnswers.single['answers'], hasLength(2));
      },
    );

    test("I'm OK is saved for the log without an alert", () async {
      final remote = ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      );
      final receipt = await remote.postRideCheckAnswers(
        submission(alert: false, answers: [RideCheckAnswer.ok(_t0)]),
      );
      expect(receipt.alerted, isFalse);
      expect(safetyMockForProcess().rideCheckAlerts, isEmpty);
      expect(safetyMockForProcess().rideCheckAnswers.single['checkId'], 'rc_1');
    });

    test('an answer without a check or ride is refused', () async {
      final mock = safetyMockForProcess();
      final hit = mock.handle(
        method: 'POST',
        path: '/api/v1/safety/ridecheck/answers',
        body: const {'answers': []},
        requestId: 'r1',
      );
      expect(hit!.status, 422);
    });

    test('sign-out forgets answers and alerts', () async {
      final remote = ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      );
      await remote.postRideCheckAnswers(submission(alert: true));
      final mock = safetyMockForProcess()..reset();
      expect(mock.rideCheckAnswers, isEmpty);
      expect(mock.rideCheckAlerts, isEmpty);
    });
  });

  group('RideCheckController gates', () {
    late SafetyController safety;
    late RideCheckController rideCheck;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      resetSafetyMockForProcess();
      SafetyStore.resetShared();
      SafetyRepository.resetShared();
      SafetyController.resetShared();
      safety = SafetyController(
        session: SafetyStore(
          local: PreferencesSafetyLocalDataSource(memoryOnly: true),
          remote: ApiSafetyRemoteDataSource(
            ApiClient(client: InProcessMockClient()),
          ),
        ),
        emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      );
      await safety.load();
      rideCheck = RideCheckController.forSafety(safety);
    });

    tearDown(() {
      rideCheck.dispose();
      RideCheckController.tripMonitoring = false;
    });

    test('opens once per trigger per ride, and never two at a time', () async {
      expect(
        await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1'),
        RideCheckOpenResult.shown,
      );
      expect(
        await rideCheck.open(RideCheckTrigger.offRoute, rideId: 'r1'),
        RideCheckOpenResult.busy,
      );
      rideCheck.imOk();
      await rideCheck.settle();
      expect(
        await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1'),
        RideCheckOpenResult.alreadyShown,
      );
      expect(
        await rideCheck.open(RideCheckTrigger.offRoute, rideId: 'r1'),
        RideCheckOpenResult.shown,
      );
    });

    test(
      'a trigger Movera turned off, or the rider switched off, does not open',
      () async {
        safetyMockForProcess().rideCheck['triggers'] = {
          ...SafetyMockApi.defaultRideCheckTriggers(),
          'longStop': {'enabled': false, 'minutes': 5},
        };
        await safety.load();
        expect(
          await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1'),
          RideCheckOpenResult.triggerOff,
        );
        expect(rideCheck.session, isNull);

        await safety.setRideCheck(false);
        expect(
          await rideCheck.open(RideCheckTrigger.offRoute, rideId: 'r1'),
          RideCheckOpenResult.riderOff,
        );
      },
    );

    test(
      'live samples open the card only while trip monitoring is on',
      () async {
        rideCheck.attachTrip(const RideCheckTripContext(rideId: 'r1'), _plan);
        final stopAt = _north(_pickup, 2000);
        void stand() {
          for (var s = 0; s <= 130; s += 5) {
            rideCheck.addSample(
              'r1',
              RideCheckSample(
                point: stopAt,
                at: _t0.add(Duration(seconds: s)),
              ),
            );
          }
        }

        stand();
        expect(rideCheck.session, isNull);

        RideCheckController.tripMonitoring = true;
        rideCheck.attachTrip(const RideCheckTripContext(rideId: 'r2'), _plan);
        for (var s = 0; s <= 130; s += 5) {
          rideCheck.addSample(
            'r2',
            RideCheckSample(
              point: stopAt,
              at: _t0.add(Duration(seconds: s)),
            ),
          );
        }
        await pumpEventQueue();
        expect(rideCheck.session?.trigger, RideCheckTrigger.longStop);
        expect(rideCheck.session?.reason.stoppedMinutes, 2);
      },
    );

    test('a car last seen standing more than 2 min ago opens the card '
        'without another fix', () async {
      RideCheckController.tripMonitoring = true;
      final stopAt = _north(_pickup, 2000);
      rideCheck.attachTrip(const RideCheckTripContext(rideId: 'r5'), _plan);
      rideCheck.addSample(
        'r5',
        RideCheckSample(
          point: stopAt,
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      rideCheck.checkStill('r5');
      await pumpEventQueue();
      expect(rideCheck.session, isNull);

      rideCheck.attachTrip(const RideCheckTripContext(rideId: 'r6'), _plan);
      rideCheck.addSample(
        'r6',
        RideCheckSample(
          point: stopAt,
          at: DateTime.now().subtract(const Duration(minutes: 2, seconds: 10)),
        ),
      );
      rideCheck.checkStill('r6');
      await pumpEventQueue();
      expect(rideCheck.session?.trigger, RideCheckTrigger.longStop);
      expect(rideCheck.session?.rideId, 'r6');
      expect(rideCheck.session?.reason.stoppedMinutes, 2);
    });

    test(
      'the trip ending far from the drop-off opens "dropped far away"',
      () async {
        RideCheckController.tripMonitoring = true;
        rideCheck.attachTrip(
          const RideCheckTripContext(
            rideId: 'r3',
            destination: RideCheckPlace(label: 'Solna centrum'),
          ),
          _plan,
        );
        expect(
          await rideCheck.tripEnded('r3', _north(_destination, 2500)),
          RideCheckOpenResult.noTrigger,
        );
        rideCheck.attachTrip(
          const RideCheckTripContext(
            rideId: 'r4',
            destination: RideCheckPlace(label: 'Solna centrum'),
          ),
          _plan,
        );
        expect(
          await rideCheck.tripEnded('r4', _north(_destination, 3500)),
          RideCheckOpenResult.shown,
        );
        expect(rideCheck.session!.reason.destinationLabel, 'Solna centrum');
        expect(
          rideCheck.session!.rows.map((row) => row.id),
          contains(RideCheckRowId.wrongPlace),
        );
      },
    );

    test('the demo plays both scenarios with admin numbers', () async {
      expect(
        await rideCheck.playDemo(
          RideCheckTrigger.droppedFar,
          rideId: 'demo-far',
        ),
        RideCheckOpenResult.shown,
      );
      final far = rideCheck.session!;
      expect(far.trigger, RideCheckTrigger.droppedFar);
      expect(far.reason.distanceMeters, greaterThan(3000));
      expect(far.reason.destinationLabel, 'Solna centrum');
      rideCheck.imOk();
      await rideCheck.settle();

      expect(
        await rideCheck.playDemo(
          RideCheckTrigger.longStop,
          rideId: 'demo-stop',
        ),
        RideCheckOpenResult.shown,
      );
      expect(rideCheck.session!.trigger, RideCheckTrigger.longStop);
      expect(rideCheck.session!.reason.stoppedMinutes, 2);
      rideCheck.imOk();
      await rideCheck.settle();

      // Played again, it opens again.
      expect(
        await rideCheck.playDemo(
          RideCheckTrigger.longStop,
          rideId: 'demo-stop',
        ),
        RideCheckOpenResult.shown,
      );
    });
  });
}
