import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty state, wallet retry, and profile rows are labeled', (
    tester,
  ) async {
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
          home: Scaffold(
            body: MoveraEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nothing here yet',
              message: 'Saved methods will show up after you add one.',
              actionLabel: 'Retry',
              onAction: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(
      find.text('Saved methods will show up after you add one.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => const MaterialApp(home: WalletHome()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsWidgets);

    final profile = ProfileController(
      store: ProfileRepository(storageKey: 'a11y_profile'),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) =>
            MaterialApp(home: AccountHomePage(controller: profile)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Personal info'), findsOneWidget);
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectMinTap(
    WidgetTester tester,
    Finder finder, {
    required String reason,
  }) {
    final size = tester.getSize(finder.first);
    expect(
      size.width,
      greaterThanOrEqualTo(MoveraIconButton.minTap),
      reason: '$reason width=${size.width}',
    );
    expect(
      size.height,
      greaterThanOrEqualTo(MoveraIconButton.minTap),
      reason: '$reason height=${size.height}',
    );
  }

  testWidgets('round icon button is 48x48 and labeled', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: MoveraIconButton.round(
          icon: Icons.my_location_rounded,
          onPressed: () {},
          label: 'Recenter map',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Recenter map'), findsOneWidget);
    expectMinTap(
      tester,
      find.bySemanticsLabel('Recenter map'),
      reason: 'round icon',
    );
  });

  testWidgets('plain icon button is 48x48 with required tooltip', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: MoveraIconButton(
          icon: Icons.close_rounded,
          onPressed: () {},
          label: 'Close',
        ),
      ),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
    expectMinTap(tester, find.byType(IconButton), reason: 'plain icon');
  });

  testWidgets('home menu and account hits are 48x48', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: PremiumTopActions(onMenuTap: () {}, onAccountTap: () {}),
      ),
    );
    expect(find.bySemanticsLabel('Menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Account'), findsOneWidget);
    final hits = find.descendant(
      of: find.byType(PremiumTopActions),
      matching: find.byType(InkWell),
    );
    expectMinTap(tester, hits.at(0), reason: 'Menu');
    expectMinTap(tester, hits.at(1), reason: 'Account');
  });

  testWidgets('completion back hit is 48x48', (tester) async {
    await pumpApp(tester, const RideCompleted());
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expectMinTap(
      tester,
      find.bySemanticsLabel('Back'),
      reason: 'Ride completed back',
    );
  });

  testWidgets('the later chip is 48x48', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: WhereToCard(
          destinationAddress: null,
          onDestinationTap: () {},
          onOpenSchedule: () {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Schedule for later'), findsOneWidget);
    expectMinTap(
      tester,
      find
          .descendant(
            of: find.byType(WhereToCard),
            matching: find.byType(InkWell),
          )
          .last,
      reason: 'Later chip',
    );
    expect(find.bySemanticsLabel('Where to?'), findsOneWidget);
  });
}
