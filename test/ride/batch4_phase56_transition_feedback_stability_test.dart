import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.ride
      ..rideId = 'phase56-completion'
      ..status = RideStatus.tripCompleted;
  });

  testWidgets(
    'RideStageTransition keeps the incoming stage opaque during handoff',
    (tester) async {
      final route = RideStageTransition<void>(const SizedBox.shrink());
      final incoming = Container(
        key: const ValueKey<String>('phase56-incoming-stage'),
        color: Colors.blue,
      );
      late Widget transition;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              transition = route.transitionsBuilder(
                context,
                const AlwaysStoppedAnimation<double>(0.35),
                const AlwaysStoppedAnimation<double>(0),
                incoming,
              );
              return Scaffold(body: transition);
            },
          ),
        ),
      );

      expect(transition, isA<Stack>());
      final stack = transition as Stack;

      expect(stack.children.length, 3);
      expect(stack.children.first, isA<ColoredBox>());
      expect(
        (stack.children.first as ColoredBox).color,
        const Color(0xFFF6F5F1),
      );
      expect(
        identical(stack.children[1], incoming),
        isTrue,
        reason: 'the incoming ride screen must be mounted at full opacity, not faded over the previous stage',
      );
      expect(stack.children[1], isNot(isA<FadeTransition>()));
      expect(stack.children[2], isA<IgnorePointer>());

      expect(
        route.transitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 120)),
      );
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion feedback keeps identical geometry while payment unlocks rating and tip',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final realtime = _Phase56CompletionRealtime();
      addTearDown(realtime.dispose);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            home: RideCompleted(
              status: RideStatus.tripCompleted,
              rideId: 'phase56-completion',
              realtime: realtime,
              showConnectionBanner: false,
            ),
          ),
        ),
      );
      await tester.pump();

      const feedbackKey = ValueKey<String>('completion-feedback');
      const lockKey = ValueKey<String>('completion-feedback-lock');
      final feedback = find.byKey(feedbackKey);

      expect(feedback, findsOneWidget);
      expect(find.text('How was your trip'), findsOneWidget);
      expect(find.text('Tip your driver'), findsOneWidget);
      expect(
        tester.widget<IgnorePointer>(find.byKey(lockKey)).ignoring,
        isTrue,
      );

      final initialRect = tester.getRect(feedback);

      realtime.emit(RideStatus.paymentProcessing);
      await tester.pump();
      expect(feedback, findsOneWidget);
      expect(tester.getRect(feedback), initialRect);

      realtime.emit(RideStatus.paymentFinalized);
      await tester.pump();
      expect(feedback, findsOneWidget);
      expect(tester.getRect(feedback), initialRect);

      realtime.emit(RideStatus.ratingPending);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final unlockedRect = tester.getRect(feedback);
      expect(unlockedRect.left, closeTo(initialRect.left, 0.01));
      expect(unlockedRect.top, closeTo(initialRect.top, 0.01));
      expect(unlockedRect.width, closeTo(initialRect.width, 0.01));
      expect(unlockedRect.height, closeTo(initialRect.height, 0.01));
      expect(
        tester.widget<IgnorePointer>(find.byKey(lockKey)).ignoring,
        isFalse,
      );
      expect(find.text('How was your trip'), findsOneWidget);
      expect(find.text('Tip your driver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Phase56CompletionRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);

  String? _rideId;
  int _sequence = 0;

  @override
  bool get supportsRiderSignals => true;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    _rideId = rideId;
    return _controller.stream;
  }

  void emit(RideStatus status) {
    final rideId = _rideId;
    if (rideId == null) return;
    _sequence += 1;
    _controller.add(
      RideRealtimeEvent(
        rideId: rideId,
        status: status,
        sequence: _sequence,
        at: DateTime(2026, 9, 24, 20, 0, _sequence),
      ),
    );
  }

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
  void dispose() {
    _controller.close();
  }
}
