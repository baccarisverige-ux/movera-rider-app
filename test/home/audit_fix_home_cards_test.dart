import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 14, 12);

Reservation _ride(String id, String category) => Reservation(
  reservationId: id,
  createdAt: DateTime(2026, 10, 1),
  scheduledPickupAt: DateTime(2026, 10, 3, 8),
  pickup: const ReservationPlace(label: 'A'),
  destination: const ReservationPlace(label: 'B'),
  categoryId: category,
  categoryName: category,
  categoryImage: 'assets/images/rides/movera.webp',
  price: 200,
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
    expect(find.text('0 rides · kr 0'), findsOneWidget);
    expect(find.text('est. CO₂ avoided'), findsOneWidget);

    rides.add(_ride('a', 'electric'));
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('1 ride · kr 200'), findsOneWidget);
    expect(find.text('0.4 kg'), findsOneWidget);
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
    expect(find.textContaining('kr 50'), findsNothing);
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
