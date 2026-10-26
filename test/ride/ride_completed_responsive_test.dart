import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpCompletion(
    WidgetTester tester, {
    required double textScale,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const RideCompleted(
            status: RideStatus.tripCompleted,
            persistOnDemandState: false,
            feedbackAvailableOnCompletion: true,
            showConnectionBanner: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('completion fits a 390x844 phone at normal text', (tester) async {
    await pumpCompletion(tester, textScale: 1);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ride-completed-done')),
      findsOneWidget,
    );
  });

  testWidgets('completion remains usable at 200% text', (tester) async {
    await pumpCompletion(tester, textScale: 2);
    expect(tester.takeException(), isNull);

    final done = find.byKey(const ValueKey<String>('ride-completed-done'));
    expect(done, findsOneWidget);
    await tester.ensureVisible(done);
    expect(tester.takeException(), isNull);
  });
}
