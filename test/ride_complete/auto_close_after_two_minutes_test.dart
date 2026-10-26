import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Realtime implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  String? _rideId;
  int _sequence = 0;
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    _rideId = rideId;
    return _events.stream;
  }

  void emit(RideStatus status) => _events.add(RideRealtimeEvent(
        rideId: _rideId!,
        status: status,
        sequence: ++_sequence,
        at: DateTime.now(),
      ));
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _events.close();
}

/// Owner, live test 2026-10-26: when the driver finished the trip while the
/// app was closed, reopening showed the finished-trip / tip screen, and it
/// stayed there for good. Owner decision: it goes Home by itself after 2
/// minutes without a touch; the trip stays in History.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(List<String>, _Realtime)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final closed = <String>[];
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.ratingPending,
          rideId: 'r-auto',
          realtime: realtime,
          persistOnDemandState: false,
          onClose: (_) async => closed.add('home'),
        ),
      ),
    ));
    await tester.pump();
    return (closed, realtime);
  }

  test('the owner\'s choice is 2 minutes', () {
    expect(RideCompleted.defaultAutoCloseAfter, const Duration(minutes: 2));
  });

  testWidgets('it goes Home by itself after 2 minutes', (tester) async {
    final (closed, _) = await open(tester);
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(closed, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(closed, ['home']);
  });

  testWidgets('a touch starts the 2 minutes again', (tester) async {
    final (closed, _) = await open(tester);
    await tester.pump(const Duration(seconds: 90));
    await tester.tap(find.text('Ride summary'), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 90));
    expect(closed, isEmpty, reason: '90 s after the touch');
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(closed, ['home']);
  });

  testWidgets('a failed payment is never closed by the timer', (tester) async {
    final (closed, realtime) = await open(tester);
    realtime.emit(RideStatus.paymentFailed);
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(closed, isEmpty);
  });
}
