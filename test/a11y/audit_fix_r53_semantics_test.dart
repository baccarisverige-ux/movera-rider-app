import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.3: small semantics checks (label, tap action, value, size)
/// for the accessibility fixes, one case per bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('rider-u64: Share trip is a 44 px named button', (tester) async {
    await pump(
      tester,
      const Scaffold(body: Center(child: WaitingShareButton())),
    );
    final handle = tester.ensureSemantics();
    final share = find.bySemanticsLabel('Share trip');
    expect(tester.getSize(share).shortestSide, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(share),
      containsSemantics(
        label: 'Share trip',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
