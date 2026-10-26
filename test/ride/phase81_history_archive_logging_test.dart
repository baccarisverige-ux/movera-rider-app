import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LogEntry {
  const _LogEntry(this.level, this.event, this.extra);

  final TelemetryLevel level;
  final String event;
  final Map<String, Object?> extra;
}

class _RecordingLogger implements LoggerSink {
  final entries = <_LogEntry>[];

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    entries.add(_LogEntry(level, event, Map<String, Object?>.from(extra)));
  }
}

RideSnapshot _snapshot() => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime(2026, 9, 26, 12),
  pickupAddress: 'Pickup',
  destinationAddress: 'Destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: 'phase81-history-ride',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    Observability.reset();
  });

  tearDown(Observability.reset);

  test('terminal History archive failure is logged and retried', () async {
    final logger = _RecordingLogger();
    Observability.configure(loggerSink: logger);

    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final ride = RideSession()..rideId = 'phase81-history-ride';
    final snapshot = _snapshot();
    await RideSnapshotStore.save(snapshot);

    var archiveAttempts = 0;
    final controller = FindingDriverController(
      realtime: realtime,
      ride: ride,
      store: FindingDriverRepository(),
      historyArchiveWriter: (_, __, ___) async {
        archiveAttempts += 1;
        if (archiveAttempts == 1) {
          throw StateError('simulated storage failure');
        }
      },
    );
    addTearDown(controller.dispose);

    controller.start(snapshot: snapshot, onTick: (_) {}, onMatched: () {});

    // rider-32: a driver drop no longer ends the search; a system cancel is
    // the terminal end that archives.
    realtime.emit(RideStatus.cancelledBySystem, sequence: 5);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(archiveAttempts, 2);
    final failures = logger.entries
        .where((entry) => entry.event == 'ride.history.archive_failed')
        .toList();
    expect(failures, hasLength(1));
    expect(failures.single.level, TelemetryLevel.warning);
    expect(failures.single.extra['rideId'], 'phase81-history-ride');
    expect(failures.single.extra['status'], 'cancelledBySystem');
    expect(failures.single.extra['attempt'], 1);
    expect(await RideSnapshotStore.read(), isNull);
  });
}
