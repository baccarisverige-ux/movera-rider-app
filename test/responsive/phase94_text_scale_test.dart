import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('empty state scrolls at 2x text on $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (context, child) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: const Scaffold(
                body: SizedBox(
                  height: 170,
                  child: MoveraEmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications yet',
                    message:
                        'Ride and account updates will appear here when they arrive.',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The production setup waits one frame for the real screen size.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('safety status fits at 2x text on $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (context, child) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: ListView(
                  children: const [
                    SafetyRow(
                      mark: SafetyMarks.contacts,
                      title: 'Emergency contact',
                      subtitle: 'Let someone know where your ride is going.',
                      status: 'Unavailable',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // The production setup waits one frame for the real screen size.
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
