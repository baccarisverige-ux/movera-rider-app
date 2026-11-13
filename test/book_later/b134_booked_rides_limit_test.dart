import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// B1.34 (contract v0.18.81, contract.json#bookLater.riderCap; owner Q94
/// "A) Yes", 2026-11-13 texts): the server refuses a booked ride over the
/// zone's maxOpenPerRider with 409 booked_rides_limit and the number in its
/// message. Before this the app showed the "can't be changed" text for it.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  test('B1.34: booked_rides_limit is a Book later refusal', () {
    expect(BookLaterRefusedException.reasons, contains('booked_rides_limit'));
  });

  test('B1.34: the rider reads the owner text with the zone number', () {
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('booked_rides_limit', limit: 3),
        ReservationAction.book,
      ),
      'You can have at most 3 booked rides. Cancel one to book another.',
    );
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('booked_rides_limit', limit: 5),
        ReservationAction.book,
      ),
      contains('at most 5 booked rides'),
    );
  });

  test('B1.34: sv and fr texts (owner words, fr « programmées », Q11)', () {
    expect(
      lookupAppLocalizations(const Locale('sv')).resErrBookedRidesLimit(3),
      'Du kan ha högst 3 bokade resor. Avboka en för att boka en ny.',
    );
    expect(
      lookupAppLocalizations(const Locale('fr')).resErrBookedRidesLimit(3),
      'Vous pouvez avoir au maximum 3 courses programmées. '
      'Annulez-en une pour en réserver une autre.',
    );
  });

  test(
    'B1.34: POST /trips 409 booked_rides_limit becomes the refusal with 3',
    () async {
      final client = MockClient((request) async {
        final quote = request.url.path == '/api/v1/quotes';
        final body = quote
            ? {
                'quotes': [
                  {
                    'quoteId': 'qte_1',
                    'categoryId': 'economy',
                    'total': {'amountMinor': 24200, 'currency': 'SEK'},
                  },
                ],
              }
            : {
                'code': 'conflict',
                'message':
                    'You can have at most 3 booked rides. Cancel one to book another.',
                'reason': 'booked_rides_limit',
              };
        return http.Response(
          jsonEncode(body),
          quote ? 200 : 409,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = ApiReservationRepository(
        api: ApiClient(client: client, env: staging),
      );
      Object? error;
      try {
        await repo.createReservation(
          ReservationDraft(
            scheduledPickupAt: DateTime.utc(2026, 11, 5, 8),
            pickup: const ReservationPlace(
              label: 'Sergels torg',
              lat: 59.3326,
              lng: 18.0649,
            ),
            destination: const ReservationPlace(
              label: 'Medborgarplatsen',
              lat: 59.3143,
              lng: 18.0735,
            ),
            categoryId: 'economy',
            categoryName: 'Economy',
            categoryImage: '',
            price: 242,
            paymentMethod: 'Cash',
          ),
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<BookLaterRefusedException>());
      final refused = error! as BookLaterRefusedException;
      expect(refused.reason, 'booked_rides_limit');
      expect(refused.limit, 3);
    },
  );
}
