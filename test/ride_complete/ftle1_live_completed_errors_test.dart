import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/calls/presentation/call_window_gate.dart';
import 'package:movera_rider/features/favourites/favourite_drivers.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => c.stream;
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
  void dispose() => c.close();
}

/// FTL-E1 (Firebase trip-lifecycle runs 2026-11-15/16, staging build):
/// `completed` FlutterError x2 and `done->home` x1. The live-only
/// "Save as a favourite driver" SwitchListTile sat on the white summary
/// card (a coloured DecoratedBox) with no Material of its own, so debug
/// builds reported "ListTile background color or ink splashes may be
/// invisible" on each build of the summary.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('en');
  });
  tearDown(() => CallDriverAfterTrip.readTrip = null);

  testWidgets('FTL-E1 favourite driver toggle on the white summary card: '
      'no FlutterError', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: const FavouriteDriverToggle(rideId: 'trp_ftle1'),
          ),
        ),
      ),
    );
    await tester.pump();
    FlutterError.onError = previous;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    expect(find.byKey(const ValueKey('favourite-driver')), findsOneWidget);
  });

  testWidgets('FTL-E1 the Switch keeps its normal hover/focus/overlay colours',
      (tester) async {
    final base = ThemeData();
    await tester.pumpWidget(
      MaterialApp(
        theme: base,
        home: const Scaffold(
          body: FavouriteDriverToggle(rideId: 'trp_ftle1_overlay'),
        ),
      ),
    );
    await tester.pump();
    final ctx = tester.element(find.byType(Switch));
    final t = Theme.of(ctx);
    // Same values the Switch sees on main (no override at all).
    expect(t.hoverColor, base.hoverColor);
    expect(t.focusColor, base.focusColor);
    expect(t.switchTheme, base.switchTheme);
    expect(t.colorScheme, base.colorScheme);
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.overlayColor, isNull);
    expect(sw.hoverColor, isNull);
    expect(sw.focusColor, isNull);
  });

  // The whole summary as the staging build shows it (contract wire on):
  // run with --dart-define=MOVERA_FLAVOR=staging
  // --dart-define=MOVERA_API_BASE_URL=https://api.staging.example.com.
  for (final st in [
    RideStatus.tripCompleted,
    RideStatus.paymentProcessing,
    RideStatus.paymentFinalized,
    RideStatus.ratingPending,
  ]) {
    for (final persist in [false, true]) {
      testWidgets(
        'FTL-E1 live completed screen at phone size: no FlutterError ${st.name} persist=$persist',
        skip: AppEnv.current.allowsMockTransport,
        (tester) async {
          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          addTearDown(() => FlutterError.onError = previous);
          CallDriverAfterTrip.readTrip = (id) async => {'tripId': id};
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 2.625;
          addTearDown(tester.view.reset);
          final realtime = _Realtime();
          addTearDown(realtime.dispose);
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                home: RideCompleted(
                  status: st,
                  rideId: 'trp_ftle1',
                  realtime: realtime,
                  persistOnDemandState: persist,
                  showConnectionBanner: false,
                  receiptLoader: (_) async => null,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const ValueKey('ride-completed-done')));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          FlutterError.onError = previous;
          expect(errors.map((e) => e.exceptionAsString()), isEmpty);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
