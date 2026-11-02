import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/features/home/presentation/widgets/liquid_glass_nav.dart';
import 'package:movera_rider/core/constants/appassets.dart';

void main() {
  testWidgets('glass mock', (t) async {
    t.view.physicalSize = const Size(780, 520);
    t.view.devicePixelRatio = 2;
    final bytes = File('test/zz/bg.png').readAsBytesSync();
    Widget bar(double f, String label) {
      return Builder(builder: (_) {
        glassFrost = f;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(width: 330, child: LiquidGlassNavRow(selectedIndex: 0, floatingFraction: 1, hitSlop: 0, itemHeight: 52, entries: [
            LiquidGlassNavEntry(iconAsset: AppAssets.solarHome, label: 'Hem', onTap: () {}),
            LiquidGlassNavEntry(iconAsset: AppAssets.solarWallet, label: 'Betalning', onTap: () {}),
            LiquidGlassNavEntry(iconAsset: AppAssets.solarCalendar, label: 'Boka i förväg', onTap: () {}),
            LiquidGlassNavEntry(iconAsset: AppAssets.solarUser, label: 'Konto', onTap: () {}),
          ])),
        ]);
      });
    }
    await t.pumpWidget(ScreenUtilInit(designSize: const Size(390, 844), minTextAdapt: true, splitScreenMode: true, builder: (_, __) => MaterialApp(debugShowCheckedModeBanner: false, home: RepaintBoundary(child: Scaffold(body: Stack(children: [
      Positioned.fill(child: Image.memory(bytes, fit: BoxFit.cover, alignment: const Alignment(0, 0.95))),
      Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [bar(1.0, 'Now'), const SizedBox(height: 18), bar(0.9, 'New: 10% less')]))),
    ]))))));
    await t.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('out.png'));
  });
}
