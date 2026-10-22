import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/home/presentation/widgets/liquid_glass_nav.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_bottom_nav_item.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<String> taps,
  double floating = 1,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  LiquidGlassNavEntry entry(String icon, String label) => LiquidGlassNavEntry(
    iconAsset: icon,
    label: label,
    onTap: () => taps.add(label),
  );
  await tester.pumpWidget(
    MoveraScreenUtilInit(
      builder: (_, __) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 360,
              child: LiquidGlassNavRow(
                floatingFraction: floating,
                entries: [
                  entry(AppAssets.solarHome, 'Home'),
                  entry(AppAssets.solarWallet, 'Payment'),
                  entry(AppAssets.solarCalendar, 'Schedule'),
                  entry(AppAssets.solarUser, 'Account'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

LiquidGlassNavRowState _state(WidgetTester tester) =>
    tester.state<LiquidGlassNavRowState>(find.byType(LiquidGlassNavRow));

void main() {
  testWidgets(
    'a tap lifts a glass lens that slides to the tab, then opens it',
    (tester) async {
      final taps = <String>[];
      await _pump(tester, taps: taps);
      expect(find.byKey(const ValueKey('liquid-glass-lens')), findsNothing);

      await tester.tap(find.text('Schedule'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('liquid-glass-lens')), findsOneWidget);
      expect(_state(tester).position, inExclusiveRange(0, 2));
      expect(
        taps,
        isEmpty,
        reason: 'the page opens once the lens has travelled',
      );

      await tester.pump(LiquidGlassNavRow.openDelay);
      expect(taps, ['Schedule']);
      await tester.pumpAndSettle();
      expect(_state(tester).position, closeTo(2, 0.01));
      expect(_state(tester).lift, 0);
      expect(find.byKey(const ValueKey('liquid-glass-lens')), findsNothing);
    },
  );

  testWidgets('the lens stays close to the icon size, not the whole bar', (
    tester,
  ) async {
    await _pump(tester, taps: []);
    await tester.tap(find.text('Account'));
    await tester.pump(const Duration(milliseconds: 40));
    final lens = tester.getRect(
      find.byKey(const ValueKey('liquid-glass-lens')),
    );
    final item = tester.getRect(find.byType(PremiumBottomNavItem).first);
    expect(lens.width, lessThanOrEqualTo(68 * 1.3));
    expect(lens.width, lessThan(item.width * 1.25));
    await tester.pumpAndSettle();
  });

  testWidgets('it also plays with the sheet up (docked bar)', (tester) async {
    final taps = <String>[];
    await _pump(tester, taps: taps, floating: 0);
    await tester.tap(find.text('Payment'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('liquid-glass-lens')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(taps, ['Payment']);
  });

  testWidgets('a drag carries the lens and selects the tab under the finger', (
    tester,
  ) async {
    final taps = <String>[];
    await _pump(tester, taps: taps);
    final from = tester.getCenter(find.text('Home'));
    final to = tester.getCenter(find.text('Account'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveTo(to);
    await tester.pump();
    expect(_state(tester).lift, 1);
    expect(_state(tester).position, closeTo(3, 0.3));
    await gesture.up();
    await tester.pump(LiquidGlassNavRow.openDelay);
    await tester.pumpAndSettle();
    expect(taps, ['Account']);
  });

  testWidgets('reduce motion: no lens, the tab opens at once', (tester) async {
    final taps = <String>[];
    await _pump(tester, taps: taps, reduceMotion: true);
    await tester.tap(find.text('Payment'));
    await tester.pump();
    expect(taps, ['Payment']);
    expect(find.byKey(const ValueKey('liquid-glass-lens')), findsNothing);
    expect(_state(tester).position, 1);
  });

  testWidgets('tapping the selected tab runs it without moving', (
    tester,
  ) async {
    final taps = <String>[];
    await _pump(tester, taps: taps);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(taps, ['Home']);
    expect(_state(tester).position, 0);
  });

  testWidgets('a tab that opens nothing over Home glides back to Home', (
    tester,
  ) async {
    final taps = <String>[];
    await _pump(tester, taps: taps);
    await tester.tap(find.text('Schedule'));
    await tester.pump();
    await tester.pump(LiquidGlassNavRow.openDelay);
    expect(taps, ['Schedule']);
    await tester.pump(LiquidGlassNavRow.coverCheck);
    await tester.pumpAndSettle();
    expect(_state(tester).position, closeTo(0, 0.01));
  });
}
