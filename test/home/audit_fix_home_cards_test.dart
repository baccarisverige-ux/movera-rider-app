import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_layout.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 14, 12);

Reservation _ride(
  String id,
  String category, {
  double price = 200,
  String currency = 'SEK',
}) => Reservation(
  reservationId: id,
  createdAt: DateTime(2026, 10, 1),
  scheduledPickupAt: DateTime(2026, 10, 3, 8),
  pickup: const ReservationPlace(label: 'A'),
  destination: const ReservationPlace(label: 'B'),
  categoryId: category,
  categoryName: category,
  categoryImage: 'assets/images/rides/movera.webp',
  price: price,
  currency: currency,
  paymentMethod: 'Cash',
  status: ReservationStatus.completed,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('FLOW-13: CO₂ avoided counts Electric rides only', () {
    final stats = MonthRideStats.fromRides([
      _ride('a', 'economy'),
      _ride('b', 'premium'),
      _ride('c', 'electric'),
    ], _now);
    expect(stats.rides, 3);
    expect(stats.co2AvoidedKg, closeTo(MonthRideStats.co2PerRideKg, 1e-9));
  });

  test('Q11: the month shows one total per currency, never converted', () {
    final stats = MonthRideStats.fromRides([
      _ride('a', 'economy', price: 24, currency: 'EUR'),
      _ride('b', 'economy', price: 500),
      _ride('c', 'economy', price: 320),
    ], _now);
    expect(stats.pillText, '3 rides · 820 kr · 24,00 €');
  });

  test('a trip whose payment failed is a ride but not money spent', () {
    final stats = MonthRideStats.fromRides([
      _ride('a', 'economy', price: 500),
      _ride('b', 'economy', price: 320).copyWith(paymentFailed: true),
    ], _now);
    expect(stats.rides, 2);
    expect(stats.pillText, '2 rides · 500 kr');
  });

  testWidgets('FLOW-13: the month card refreshes when a ride is archived and '
      'labels CO₂ as an estimate', (tester) async {
    final rides = <Reservation>[];
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    await _pump(
      tester,
      HomeJourneySection(
        onDestinationTap: () {},
        onOpenSchedule: () {},
        ridesLoader: () async => List.of(rides),
        clock: () => _now,
        changes: changes.stream,
      ),
    );
    expect(find.text('0 rides'), findsOneWidget);
    expect(find.text('est. CO₂ avoided'), findsOneWidget);

    rides.add(_ride('a', 'electric'));
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('1 ride · 200 kr'), findsOneWidget);
    expect(find.text('0.4 kg'), findsOneWidget);
  });

  testWidgets('owner round 1: no Help centre on the sheet; even gaps, one '
      'radius and taller journey cards', (tester) async {
    await _pump(
      tester,
      HomeJourneySection(
        onDestinationTap: () {},
        onOpenSchedule: () {},
        ridesLoader: () async => const [],
        clock: () => _now,
        changes: const Stream<void>.empty(),
      ),
    );
    expect(find.text('Help centre'), findsNothing);
    final cards = [
      for (final title in [
        'Catch your flight',
        'Comfort car',
        'Highly rated chauffeur',
      ])
        find
            .ancestor(of: find.text(title), matching: find.byType(InkWell))
            .first,
    ];
    for (final card in cards) {
      expect(
        tester.getSize(card).height,
        closeTo(ResSize.h * journeyCardHeightDesign, 0.01),
      );
      expect(
        tester.widget<InkWell>(card).borderRadius,
        BorderRadius.circular(HomeSheetLayout.cardRadius),
      );
    }
    // The month card and the "Start your journey" heading are one section
    // gap apart.
    final month = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('Your'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).color ==
                      const Color(0xFFF3F4F5),
            ),
          )
          .first,
    );
    final heading = tester.getRect(find.text('START YOUR JOURNEY'));
    expect(
      heading.top - month.bottom,
      closeTo(HomeSheetLayout.sectionGap, 0.01),
    );
  });

  test('help stays reachable from Account and the side menu', () {
    // Owner round 1: the Home sheet no longer links Help centre; these two
    // entry points must stay.
    for (final path in [
      'lib/features/profile/presentation/account_home.dart',
      'lib/features/home/presentation/side_menu.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('SupportHome()'),
        reason: path,
      );
    }
  });

  testWidgets('NAV-11: Comfort and top-rated cards preselect their category', (
    tester,
  ) async {
    final asked = <String>[];
    var plain = 0;
    await _pump(
      tester,
      HomeJourneySection(
        onDestinationTap: () => plain++,
        onOpenSchedule: () {},
        onRideTypeTap: asked.add,
        ridesLoader: () async => const [],
        clock: () => _now,
        changes: const Stream<void>.empty(),
      ),
    );
    await tester.tap(find.text('Comfort car'));
    await tester.tap(find.text('Highly rated chauffeur'));
    await tester.pump();
    expect(asked, ['comfort', 'premium']);
    expect(plain, 0);
  });

  Future<void> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: RiderMenuPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('NAV-11 / FLOW-16: the referral card promises no reward', (
    tester,
  ) async {
    await pumpMenu(tester);
    expect(find.textContaining('50 kr'), findsNothing);
    expect(find.text('Coming soon: invite friends to Movera.'), findsOneWidget);
  });

  testWidgets('FLOW-17: the menu header follows a profile rename', (
    tester,
  ) async {
    final profile = AppScope.instance.profile;
    final before = profile.profile;
    addTearDown(() => tester.runAsync(() => profile.update(before)));
    await tester.runAsync(
      () => profile.update(before.copyWith(name: 'Ada Lovelace')),
    );
    await pumpMenu(tester);
    expect(find.textContaining('Ada'), findsWidgets);

    await tester.runAsync(
      () => profile.update(before.copyWith(name: 'Grace Hopper')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Grace'), findsWidgets);
    expect(find.textContaining('Ada'), findsNothing);
  });
}
