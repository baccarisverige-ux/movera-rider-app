import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
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

/// Owner decision 2026-10-26: movera-server takes no tips yet
/// (`tips_not_available`), so a tip picked in the live app was silently
/// never paid. Tips are hidden until they are; rating stays.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, {bool? tipsAvailable}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.ratingPending,
          rideId: 'r-tips',
          realtime: realtime,
          persistOnDemandState: false,
          tipsAvailable: tipsAvailable,
          onClose: (_) async {},
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the live app offers rating but no tip', (tester) async {
    await open(tester, tipsAvailable: false);
    expect(find.byType(RideCompletedGiveReview), findsOneWidget);
    expect(find.byType(RideCompletedAddTip), findsNothing);
  });

  testWidgets('where tips are taken (the demo) the tip choice stays',
      (tester) async {
    await open(tester);
    expect(find.byType(RideCompletedAddTip), findsOneWidget);
  });
}
