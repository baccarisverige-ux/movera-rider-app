import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/features/ride_complete/presentation/driver_info.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
  }

  Future<void> pumpResponsive(
    WidgetTester tester,
    Widget screen, {
    required Size viewport,
    required String label,
  }) async {
    await tester.pumpWidget(
      // UI-11: the app's own ScreenUtil setup.
      MoveraScreenUtilInit(
        key: ValueKey('${viewport.width}x${viewport.height}-$label'),
        builder: (_, __) => MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason:
          '$label overflowed or threw at '
          '${viewport.width.toInt()}x${viewport.height.toInt()}',
    );
  }

  const completionViewports = [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
    Size(768, 1024),
    Size(844, 390),
  ];

  for (final viewport in completionViewports) {
    testWidgets('ride completion fits ${viewport.width.toInt()}x'
        '${viewport.height.toInt()}', (tester) async {
      await setViewport(tester, viewport);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpResponsive(
        tester,
        const RideCompleted(),
        viewport: viewport,
        label: 'Ride completion',
      );
    });
  }

  const componentViewport = Size(390, 844);
  final completionComponents = <(String, Widget)>[
    ('Completion driver', const RideCompletedDriverInfo()),
    ('Completion rating', const RideCompletedGiveReview()),
    ('Completion tip', const RideCompletedAddTip()),
    ('Completion receipt', const RideCompletedTripDetail()),
  ];
  for (final entry in completionComponents) {
    testWidgets('${entry.$1} fits independently', (tester) async {
      await setViewport(tester, componentViewport);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpResponsive(
        tester,
        Scaffold(body: SingleChildScrollView(child: entry.$2)),
        viewport: componentViewport,
        label: entry.$1,
      );
    });
  }

  const generalViewports = [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
    Size(844, 390),
  ];

  for (final viewport in generalViewports) {
    for (final name in const [
      'Notifications',
      'Support',
      'Profile',
      'History',
      'Schedule',
      'Wallet',
    ]) {
      testWidgets('$name fits ${viewport.width.toInt()}x'
          '${viewport.height.toInt()}', (tester) async {
        await setViewport(tester, viewport);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final profile = ProfileController(
          store: ProfileRepository(storageKey: 'responsive_profile'),
        );
        final reservations = ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
        );
        final screen = switch (name) {
          'Notifications' => const NotificationScreen(),
          'Support' => const SupportHome(),
          'Profile' => AccountHomePage(controller: profile),
          'History' => RideHistory(reservations: reservations),
          'Schedule' => const ScheduleRide(),
          'Wallet' => const WalletHome(),
          _ => throw StateError('Unknown responsive screen: $name'),
        };
        await pumpResponsive(tester, screen, viewport: viewport, label: name);
      });
    }
  }

  testWidgets('account editor remains usable with a mobile keyboard inset', (
    tester,
  ) async {
    await setViewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final profile = ProfileController(
      store: ProfileRepository(storageKey: 'keyboard_profile'),
    );
    await profile.hydrate();

    const env = AppEnv(
      flavor: AppFlavor.test,
      apiBaseUrl: 'https://api.test.movera.invalid',
    );
    final security = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(env: env, client: InProcessMockClient()),
      ),
    );
    await security.load();

    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: PersonalInfoPage(
            controller: profile,
            securityController: security,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Name').first);
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final saveBottom = tester.getBottomRight(find.text('Save')).dy;
    expect(
      saveBottom,
      lessThanOrEqualTo(844 - 320),
      reason: 'Save must remain above the simulated software keyboard.',
    );
  });
}
