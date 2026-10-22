import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-24: a history read that fails is not shown as '0 rides'.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a failed read shows no ride count', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeJourneySection(
              onDestinationTap: () {},
              onOpenSchedule: () {},
              ridesLoader: () async => throw StateError('offline'),
              clock: () => DateTime(2026, 10, 14, 12),
              changes: const Stream<void>.empty(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('0 rides'), findsNothing);
  });
}
