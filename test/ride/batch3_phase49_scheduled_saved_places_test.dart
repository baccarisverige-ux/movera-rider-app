import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unknown explicit lifecycle is rejected without breaking legacy missing status', () {
    final raw = <String, dynamic>{
      'reservationId': 'rsv-49',
      'createdAt': '2026-09-24T00:00:00Z',
      'scheduledPickupAt': '2026-09-25T10:00:00Z',
      'pickup': {'label': 'Pickup'},
      'destination': {'label': 'Destination'},
      'categoryId': 'economy',
      'categoryName': 'Movera',
      'categoryImage': 'ride.webp',
      'price': 200,
      'paymentMethod': 'Card',
      'status': 'future_backend_status',
    };

    expect(ReservationStatus.tryParse('future_backend_status'), isNull);
    expect(Reservation.tryParse(raw), isNull);

    final legacy = Map<String, dynamic>.from(raw)..remove('status');
    expect(Reservation.tryParse(legacy)?.status, ReservationStatus.scheduled);
  });

  test('saved place shortcuts survive controller restart without demo data', () async {
    final first = SavedPlacesController();
    await first.save(
      const PlaceShortcut(
        title: 'Home',
        subtitle: 'Klockarvägen 37',
        kind: 'home',
      ),
    );

    final second = SavedPlacesController();
    await second.hydrate();

    expect(second.shortcuts(), hasLength(1));
    expect(second.shortcuts().single.title, 'Home');
    expect(second.shortcuts().single.subtitle, 'Klockarvägen 37');
    expect(second.shortcuts().single.kind, 'home');
  });

  test('saving same saved-place kind updates instead of duplicating it', () async {
    final controller = SavedPlacesController();
    await controller.save(
      const PlaceShortcut(title: 'Home', subtitle: 'Old', kind: 'home'),
    );
    await controller.save(
      const PlaceShortcut(title: 'Home', subtitle: 'New', kind: 'HOME'),
    );

    expect(controller.shortcuts(), hasLength(1));
    expect(controller.shortcuts().single.subtitle, 'New');
  });
}
