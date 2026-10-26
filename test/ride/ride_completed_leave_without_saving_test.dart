import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppScope.instance.ride
      ..rideId = 'ride-leave-1'
      ..status = RideStatus.ratingPending;
  });

  Widget app() {
    return ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: const Scaffold(body: Text('home-root')),
      ),
    );
  }

  // Disposed explicitly at the end of each test body instead of via
  // addTearDown: Flutter's end-of-test timer invariant runs right after the
  // test body returns, before any addTearDown callback fires.
  MockRideRealtime pushRideCompleted(InProcessMockClient backend) {
    final realtime = MockRideRealtime(api: ApiClient(client: backend));
    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => RideCompleted(
          status: RideStatus.ratingPending,
          rideId: 'ride-leave-1',
          realtime: realtime,
          controller: RideCompleteController(
            feedback: RideFeedbackRepository(api: ApiClient(client: backend)),
          ),
          showConnectionBanner: false,
        ),
      ),
    );
    return realtime;
  }

  Future<void> setViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Back with nothing selected leaves immediately, no dialog', (
    tester,
  ) async {
    await setViewport(tester);
    final backend = InProcessMockClient();
    backend.rides['ride-leave-1'] = {
      'id': 'ride-leave-1',
      'status': 'ratingPending',
    };

    await tester.pumpWidget(app());
    final realtime = pushRideCompleted(backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Leave without sending?'), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    expect(backend.rides['ride-leave-1']!['feedback'], isNull);
    realtime.dispose();
  });

  testWidgets('Back with a rating selected prompts, and Stay keeps the draft', (
    tester,
  ) async {
    await setViewport(tester);
    final backend = InProcessMockClient();
    backend.rides['ride-leave-1'] = {
      'id': 'ride-leave-1',
      'status': 'ratingPending',
    };

    await tester.pumpWidget(app());
    final realtime = pushRideCompleted(backend);
    await tester.pumpAndSettle();

    final star = find.byIcon(Icons.star_rounded).first;
    await tester.ensureVisible(star);
    await tester.tap(star);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Leave without sending?'), findsOneWidget);
    expect(backend.rides['ride-leave-1']!['feedback'], isNull);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    // Still on the completion surface; nothing was submitted.
    expect(find.byType(RideCompleted), findsOneWidget);
    expect(backend.rides['ride-leave-1']!['feedback'], isNull);
    realtime.dispose();
  });

  testWidgets(
    'Back with a rating selected, then Leave, discards it without submitting',
    (tester) async {
      await setViewport(tester);
      final backend = InProcessMockClient();
      backend.rides['ride-leave-1'] = {
        'id': 'ride-leave-1',
        'status': 'ratingPending',
      };

      await tester.pumpWidget(app());
      final realtime = pushRideCompleted(backend);
      await tester.pumpAndSettle();

      final star = find.byIcon(Icons.star_rounded).first;
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('completion-leave-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('home-root'), findsOneWidget);
      expect(backend.rides['ride-leave-1']!['feedback'], isNull);
      expect(AppScope.instance.ride.status, RideStatus.closed);
      realtime.dispose();
    },
  );

  testWidgets('Done still submits the selected rating and tip', (tester) async {
    await setViewport(tester);
    final backend = InProcessMockClient();
    backend.rides['ride-leave-1'] = {
      'id': 'ride-leave-1',
      'status': 'ratingPending',
    };

    await tester.pumpWidget(app());
    final realtime = pushRideCompleted(backend);
    await tester.pumpAndSettle();

    final star = find.byIcon(Icons.star_rounded).first;
    await tester.ensureVisible(star);
    await tester.tap(star);
    await tester.pump();

    final done = find.byKey(const ValueKey('ride-completed-done'));
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(find.text('home-root'), findsOneWidget);
    expect(backend.rides['ride-leave-1']!['feedback'], isNotNull);
    expect(AppScope.instance.ride.status, RideStatus.closed);
    realtime.dispose();
  });
}
