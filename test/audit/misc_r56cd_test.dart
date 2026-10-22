import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';

/// Wave 5 R5.6 parts c + d: everything else (low). One test per bug.

/// Storage whose writes fail once [fail] is set (quota, blocked storage).
class _FlakyStorage extends MemoryReservationStorage {
  bool fail = false;

  @override
  Future<void> write(String json) async {
    if (fail) throw StateError('storage full');
    await super.write(json);
  }
}

final _pickupAt = DateTime(2026, 9, 23, 6, 55);

ReservationDraft _draft({String? note}) => ReservationDraft(
  scheduledPickupAt: _pickupAt,
  estimatedDropoffAt: _pickupAt.add(const Duration(minutes: 30)),
  pickup: const ReservationPlace(label: 'Klockarvägen 37'),
  destination: const ReservationPlace(label: 'Arlanda Express'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 522,
  paymentMethod: 'Cash',
  note: note,
);

Future<ReservationController> _reservations(ReservationStorage storage) async {
  final c = ReservationController(
    store: LocalReservationRepository(storage: storage, nextId: () => 'rsv_1'),
  );
  await c.create(_draft());
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('rider-j8-4: a 0.35 € edit is a real price change', () {
    const change = ReservationPriceChange(
      previous: 12.35,
      next: 12.70,
      currency: 'EUR',
    );
    expect(change.unchanged, isFalse);
    expect(change.summary, contains('0,35 €'));
  });

  testWidgets('rider-j8-6: a failed no-driver resolve says so', (tester) async {
    final storage = _FlakyStorage();
    final c = await _reservations(storage);
    var rebooked = 0;
    final late = _pickupAt.add(const Duration(minutes: 6));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeReservationChrono(
            controller: c,
            now: () => late,
            onRebook: () => rebooked++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    storage.fail = true;
    await tester.tap(find.byKey(const Key('reservation-no-driver-rebook')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(rebooked, 0);
    expect(c.byId('rsv_1')!.status.isUpcoming, isTrue);
  });
}
