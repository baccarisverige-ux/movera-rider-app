import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';

/// Batch 10 Phase 111 — Home countdown chrono, option B (status badge).
///
/// The ring stays neutral (red only for "no driver found") and a 20 px corner
/// badge carries the state: check = a driver is really assigned, clock =
/// booked with no driver yet, dots = searching, ! = no driver found.
///
/// Two groups, labelled honestly:
/// - "badge per state" is the new behaviour. It fails on the base branch
///   (no badge; a booked ride with no driver shows the green "confirmed"
///   ring there).
/// - "unchanged contract" is a regression guard: semantics labels, tap
///   behaviour and the 54x54 footprint. It passes on base and must keep
///   passing.
///
/// Behavioural only: no source reads. Colours are literals so the file also
/// compiles on the base branch.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const neutralRing = Color(0x55172127);
  const bookedGrey = Color(0xFF6B757B);
  final pickupAt = DateTime(2026, 10, 2, 9, 30);

  Future<ReservationController> seeded() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_111',
      ),
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: pickupAt,
        estimatedDropoffAt: pickupAt.add(const Duration(minutes: 30)),
        pickup: const ReservationPlace(label: 'Klockarvägen 37'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
      ),
    );
    return c;
  }

  /// One state of the chrono: how to put the ride there, the fake clock, and
  /// what the rider must see / hear / get on tap.
  final states =
      <
        ({
          String name,
          Future<void> Function(ReservationController c) arrange,
          Duration offset,
          String badgeKey,
          IconData badgeIcon,
          Color badgeColor,
          Color ring,
          String semantics,
          String fullSemantics,
          bool opensNoDriverSheet,
        })
      >[
        (
          name: 'confirmed (driverAssigned + driver)',
          arrange: (c) async {
            await c.applyDriverAssignment(
              'rsv_111',
              driver: const ReservationDriver(firstName: 'Amina'),
            );
          },
          offset: const Duration(minutes: -25),
          badgeKey: 'reservation-chrono-badge-confirmed',
          badgeIcon: Icons.check_rounded,
          badgeColor: HomeReservationChrono.confirmed,
          ring: neutralRing,
          semantics: 'Reservation in 25m',
          fullSemantics: 'Reservation in 25m\n25m',
          opensNoDriverSheet: false,
        ),
        (
          name: 'booked, no driver yet (scheduled)',
          arrange: (c) async {},
          offset: const Duration(hours: -2, minutes: -15),
          badgeKey: 'reservation-chrono-badge-booked',
          badgeIcon: Icons.schedule_rounded,
          badgeColor: bookedGrey,
          ring: neutralRing,
          semantics: 'Reservation in 2h 15m',
          fullSemantics: 'Reservation in 2h 15m\n2h\n15m',
          opensNoDriverSheet: false,
        ),
        (
          name: 'searching (driverAssignmentPending)',
          arrange: (c) async {
            // Existing env-gated API: no driver argument -> pending, nobody.
            await c.assignMockDriver('rsv_111');
          },
          offset: const Duration(minutes: -12),
          badgeKey: 'reservation-chrono-badge-searching',
          badgeIcon: Icons.more_horiz_rounded,
          badgeColor: HomeReservationChrono.searching,
          ring: neutralRing,
          semantics: 'Reservation in 12m',
          fullSemantics: 'Reservation in 12m\n12m',
          opensNoDriverSheet: false,
        ),
        (
          name: 'no driver found (T+6, no driver)',
          arrange: (c) async {},
          offset: const Duration(minutes: 6),
          badgeKey: 'reservation-chrono-badge-no-driver',
          badgeIcon: Icons.priority_high_rounded,
          badgeColor: HomeReservationChrono.noDriver,
          ring: HomeReservationChrono.noDriver,
          semantics: 'No driver found. Rebook or cancel',
          fullSemantics: 'No driver found. Rebook or cancel',
          opensNoDriverSheet: true,
        ),
      ];

  const allBadgeKeys = [
    'reservation-chrono-badge-confirmed',
    'reservation-chrono-badge-booked',
    'reservation-chrono-badge-searching',
    'reservation-chrono-badge-no-driver',
  ];

  Future<void> pumpChrono(
    WidgetTester tester,
    ReservationController c,
    DateTime now,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HomeReservationChrono(controller: c, now: () => now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The no-driver state proactively opens its sheet once; close it so the
  /// tap under test starts from a clean Home.
  Future<void> dismissAutoPrompt(WidgetTester tester) async {
    if (find
        .byKey(const Key('reservation-no-driver-found'))
        .evaluate()
        .isEmpty) {
      return;
    }
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reservation-no-driver-found')), findsNothing);
  }

  Future<void> expectTapOutcome(
    WidgetTester tester,
    bool opensNoDriverSheet,
  ) async {
    if (opensNoDriverSheet) {
      expect(
        find.byKey(const Key('reservation-no-driver-found')),
        findsOneWidget,
      );
      expect(find.byType(UpcomingReservationPage), findsNothing);
    } else {
      expect(find.byType(UpcomingReservationPage), findsOneWidget);
      expect(find.text('Upcoming ride'), findsOneWidget);
      expect(
        find.byKey(const Key('reservation-no-driver-found')),
        findsNothing,
      );
    }
  }

  Finder face() => find.descendant(
    of: find.byType(HomeReservationChrono),
    matching: find.byType(CustomPaint),
  );

  group('badge per state (new; fails on base)', () {
    for (final s in states) {
      testWidgets('${s.name}: ${s.badgeKey}, ring and no other badge', (
        tester,
      ) async {
        final c = await seeded();
        await s.arrange(c);
        await pumpChrono(tester, c, pickupAt.add(s.offset));

        // Ring: neutral, red only for no-driver; never the old green.
        expect(
          tester.renderObject(face().first),
          paints..circle(color: s.ring, style: PaintingStyle.stroke),
        );
        expect(
          tester.renderObject(face().first),
          isNot(
            paints..circle(
              color: HomeReservationChrono.confirmed,
              style: PaintingStyle.stroke,
            ),
          ),
        );

        final badge = find.byKey(ValueKey<String>(s.badgeKey));
        expect(badge, findsOneWidget);
        for (final other in allBadgeKeys.where((k) => k != s.badgeKey)) {
          expect(find.byKey(ValueKey<String>(other)), findsNothing);
        }
        final deco =
            tester.widget<Container>(badge).decoration! as BoxDecoration;
        expect(deco.color, s.badgeColor);
        expect(deco.shape, BoxShape.circle);
        expect(
          find.descendant(of: badge, matching: find.byIcon(s.badgeIcon)),
          findsOneWidget,
        );
        expect(tester.getSize(badge), const Size(20, 20));
      });
    }

    testWidgets('driverAssigned status without a driver is NOT confirmed: '
        'clock badge, neutral ring', (tester) async {
      final c = await seeded();
      await c.update(
        'rsv_111',
        const ReservationPatch(
          status: ReservationStatus.driverAssigned,
          clearDriver: true,
        ),
      );
      expect(c.byId('rsv_111')!.status, ReservationStatus.driverAssigned);
      expect(c.byId('rsv_111')!.driver, isNull);
      await pumpChrono(
        tester,
        c,
        pickupAt.subtract(const Duration(minutes: 20)),
      );
      expect(
        find.byKey(const ValueKey<String>('reservation-chrono-badge-booked')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('reservation-chrono-badge-confirmed'),
        ),
        findsNothing,
      );
      expect(
        tester.renderObject(face().first),
        paints..circle(color: neutralRing, style: PaintingStyle.stroke),
      );
    });

    for (final s in states) {
      testWidgets('${s.name}: tapping the badge does the same as the disc', (
        tester,
      ) async {
        final c = await seeded();
        await s.arrange(c);
        await pumpChrono(tester, c, pickupAt.add(s.offset));
        await dismissAutoPrompt(tester);
        final badge = find.byKey(ValueKey<String>(s.badgeKey));
        // The badge's lower-left quarter sits over the disc's box.
        final chrono = tester.getRect(find.byType(HomeReservationChrono));
        final inside = tester.getCenter(badge) + const Offset(-4, 4);
        expect(chrono.contains(inside), isTrue);
        await tester.tapAt(inside);
        await tester.pumpAndSettle();
        await expectTapOutcome(tester, s.opensNoDriverSheet);
      });
    }
  });

  group('unchanged contract (regression guard; passes on base)', () {
    for (final s in states) {
      testWidgets('${s.name}: 54x54, same semantics label, badge silent, '
          'tap opens the same thing', (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await seeded();
        await s.arrange(c);
        await pumpChrono(tester, c, pickupAt.add(s.offset));
        await dismissAutoPrompt(tester);

        expect(
          tester.getSize(find.byType(HomeReservationChrono)),
          const Size(54, 54),
        );
        // The chrono's one button node: the existing label (plus the visible
        // countdown text Flutter already merges into it), nothing from the
        // badge.
        final node = tester.getSemantics(
          find.descendant(
            of: find.byType(HomeReservationChrono),
            matching: find.byType(Image),
          ),
        );
        expect(node.label, s.fullSemantics);
        expect(node.label, startsWith(s.semantics));
        expect(node, isSemantics(isButton: true, hasTapAction: true));
        if (s.opensNoDriverSheet) {
          expect(
            find.byKey(const Key('reservation-chrono-no-driver')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const Key('reservation-chrono-no-driver')),
            findsNothing,
          );
        }

        await tester.tap(find.byType(HomeReservationChrono));
        await tester.pumpAndSettle();
        await expectTapOutcome(tester, s.opensNoDriverSheet);
        semantics.dispose();
      });
    }

    testWidgets('countdown text keeps its sizes (booked 2h / 15m)', (
      tester,
    ) async {
      final c = await seeded();
      await pumpChrono(
        tester,
        c,
        pickupAt.subtract(const Duration(hours: 2, minutes: 15)),
      );
      expect(tester.widget<Text>(find.text('2h')).style!.fontSize, 11);
      expect(tester.widget<Text>(find.text('15m')).style!.fontSize, 9);
    });
  });
}
