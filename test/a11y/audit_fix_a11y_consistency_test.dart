import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/bundled_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_bottom_nav_item.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contrast_test.dart' show contrastRatio;

const _white = Color(0xFFFFFFFF);

Future<void> _pump(WidgetTester tester, Widget home, {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MoveraScreenUtilInit(
      builder: (_, __) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  // ScreenUtil waits one frame for the screen size.
  await tester.pump();
  await tester.pump();
}

class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.files);

  final List<String> files;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') throw FlutterError('no $key');
    final manifest = {
      for (final f in files)
        f: [
          {'asset': f},
        ],
    };
    return const StandardMessageCodec().encodeMessage(manifest)!;
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode((await load(key)).buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('UI-6 text greys reach 4.5:1 on their background', () {
    test('shared greys', () {
      expect(contrastRatio(AppColor.subtitle, _white), greaterThan(4.5));
      expect(contrastRatio(AppColor.hintText, _white), greaterThan(4.5));
      expect(contrastRatio(MoveraTokens.subtle, _white), greaterThan(4.5));
      for (final fill in const [Color(0xFFF3F4F5), Color(0xFFF6F8FA)]) {
        expect(
          contrastRatio(MoveraTokens.subtleOnFill, fill),
          greaterThan(4.5),
          reason: '$fill',
        );
      }
    });

    test('feature greys', () {
      expect(contrastRatio(kAccountMuted, kAccountSoft), greaterThan(4.5));
      expect(
        contrastRatio(kReservationMuted, kReservationSoft),
        greaterThan(4.5),
      );
      expect(
        contrastRatio(AuthColors.faint, AuthColors.ground),
        greaterThan(4.5),
      );
    });

    testWidgets('inactive bottom-nav label and the menu version line', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: PremiumBottomNavItem(
            iconAsset: AppAssets.solarHome,
            label: 'Payment',
            onTap: () {},
          ),
        ),
      );
      final nav = tester.widget<Text>(find.text('Payment'));
      expect(contrastRatio(nav.style!.color!, _white), greaterThan(4.5));

      await _pump(tester, const RiderMenuPage());
      await tester.pump(const Duration(milliseconds: 200));
      final version = tester.widget<Text>(
        find.textContaining('Movera Rider v'),
      );
      expect(contrastRatio(version.style!.color!, _white), greaterThan(4.5));
    });
  });

  testWidgets('UI-8: the nav label follows the system text size', (
    tester,
  ) async {
    await _pump(
      tester,
      Scaffold(
        body: PremiumBottomNavItem(
          iconAsset: AppAssets.solarHome,
          label: 'Home',
          onTap: () {},
        ),
      ),
      scale: 2,
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text('Home'));
    expect(paragraph.textScaler.scale(10), 20);
  });

  group('UI-7: values are part of the label', () {
    testWidgets('menu wallet card reads its balance', (tester) async {
      await _pump(tester, const RiderMenuPage());
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.bySemanticsLabel(RegExp(r'^Wallet, \d+ kr$')),
        findsOneWidget,
      );
    });

    testWidgets('safety row reads subtitle and status', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: SafetyRow(
            mark: SafetyMarks.contacts,
            title: 'Emergency contacts',
            subtitle: 'Choose trusted contacts.',
            status: 'Unavailable',
            onTap: () {},
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Emergency contacts, Choose trusted contacts., Unavailable',
        ),
        findsOneWidget,
      );
    });
  });

  group('UI-14: no new load on rebuild', () {
    testWidgets('menu wallet balance future is kept', (tester) async {
      await _pump(tester, const RiderMenuPage());
      await tester.pump(const Duration(milliseconds: 200));
      Future<Money>? future() => tester
          .widget<FutureBuilder<Money>>(find.byType(FutureBuilder<Money>))
          .future;
      final first = future();
      tester.element(find.byType(RiderMenuPage)).markNeedsBuild();
      await tester.pump();
      expect(identical(future(), first), isTrue);
    });

    testWidgets('auth gate reads the session once', (tester) async {
      var reads = 0;
      final never = Completer<bool>();
      Widget? gate;
      final coordinator = RideRestoreCoordinator(
        reader: () async => null,
        authRequired: () => true,
        hasSession: () {
          reads += 1;
          return never.future;
        },
        resync: (_) async {},
      )..onReplaceRoot = (page) => gate = page;
      coordinator.goHome();
      expect(gate, isNotNull);
      await _pump(tester, gate!);
      for (var i = 0; i < 3; i++) {
        tester.element(find.byWidget(gate!)).markNeedsBuild();
        await tester.pump();
      }
      expect(reads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('UI-15: bundled Poppins switches font downloads off', () {
    tearDown(() => GoogleFonts.config.allowRuntimeFetching = false);

    test('every weight bundled -> no runtime fetching', () async {
      GoogleFonts.config.allowRuntimeFetching = true;
      final bundled = await configureBundledFonts(
        bundle: _ManifestBundle([
          for (final f in bundledPoppinsFiles) 'assets/google_fonts/$f',
        ]),
      );
      expect(bundled, isTrue);
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    });

    test('a weight missing -> fetching stays on', () async {
      GoogleFonts.config.allowRuntimeFetching = true;
      final bundled = await configureBundledFonts(
        bundle: _ManifestBundle([
          for (final f in bundledPoppinsFiles.skip(1)) 'assets/google_fonts/$f',
        ]),
      );
      expect(bundled, isFalse);
      expect(GoogleFonts.config.allowRuntimeFetching, isTrue);
    });
  });
}
