import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Logs implements LoggerSink {
  final events = <(String, Map<String, Object?>)>[];

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    events.add((event, Map<String, Object?>.from(extra)));
  }

  List<Object?> causes(String event) => [
    for (final (name, extra) in events)
      if (name == event) extra['cause'],
  ];
}

RideRestoreCoordinator _coordinator({
  required bool signedIn,
  RideSnapshot? snapshot,
  bool skipRestore = false,
}) => RideRestoreCoordinator(
  reader: () async => snapshot,
  authRequired: () => false,
  authPreview: () => true,
  hasSession: () async => signedIn,
  skipRestore: () => skipRestore,
  serverActiveTrip: () async => null,
);

/// Owner (iPhone PWA): sliding the categories sheet made Safari reload the
/// tab, and the installed app's `?auth_preview=1` showed Sign in although
/// the rider was still signed in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Logs logs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Observability.reset();
    logs = _Logs();
    Observability.configure(loggerSink: logs);
  });

  tearDown(Observability.reset);

  test('signed in + preview + no ride: a reload restores Home', () async {
    final page = await _coordinator(signedIn: true).root();
    expect(page, isA<Home>());
    expect(page, isNot(isA<SignIn>()));
    expect(logs.causes('auth.root'), ['preview_session_kept']);
  });

  test('signed in + preview + skipRestore: still Home', () async {
    final page = await _coordinator(signedIn: true, skipRestore: true).root();
    expect(page, isA<Home>());
  });

  test('new tester (no session) still sees the Sign in preview', () async {
    final page = await _coordinator(signedIn: false).root();
    expect(page, isA<SignIn>());
    expect(logs.causes('auth.root'), ['cold_boot_preview']);
  });

  test('signed in + preview + live ride: the ride restores', () async {
    final snapshot = RideSnapshot(
      status: RideStatus.driverAssigned,
      savedAt: DateTime.now(),
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: 'preview-r1',
    );
    final page = await _coordinator(signedIn: true, snapshot: snapshot).root();
    expect(page, isA<WaitingForDriver>());
  });
}
