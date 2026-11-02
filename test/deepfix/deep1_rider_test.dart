import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/legal/rider_legal.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/presentation/widgets/need_help.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/app_language_store.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/server_receipt_lines.dart';
import 'package:movera_rider/features/support/domain/support_details.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deep-fix round 1 (2026-11-02): rider items from the live sweep and the
/// deep re-check, through the app's real code paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    L10n.use('en');
  });

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  group('H-4 a trip the rider ended early is a paid, completed trip', () {
    test('History lists it under Completed with the server total', () async {
      final mock = InProcessMockClient();
      mock.rides['ride_fr'] = {
        'id': 'ride_fr',
        'status': 'cancelledByRider',
        'version': 7,
        'updatedAt': '2026-11-02T09:00:00.000Z',
        'categoryId': 'economy',
        'paymentMethodId': 'cash',
        'price': 12,
        'currency': 'EUR',
        'pickupAddress': 'Hôtel de Ville, Paris',
        'pickupLat': 48.8566,
        'pickupLng': 2.3522,
        'destinationAddress': 'Gare de Lyon, Paris',
        'destinationLat': 48.8443,
        'destinationLng': 2.3743,
        'finish': {
          'endedEarly': true,
          'endedBy': 'rider',
          'total': {'amountMinor': 480, 'currency': 'EUR'},
          'cashToCollect': {'amountMinor': 480, 'currency': 'EUR'},
          'ratingAllowed': true,
        },
      };
      final history = await ApiRideHistoryRepository(
        api: ApiClient(client: mock, env: demo),
      ).loadOnDemand();
      final ride = history.single;
      expect(ride.status, ReservationStatus.completed);
      expect(ride.endedEarly, isTrue);
      expect(ride.chargedFare?.amountMinor, 480);
      expect(ride.chargedFare?.currency, 'EUR');
    });

    test('a plain rider cancel stays Cancelled', () async {
      final mock = InProcessMockClient();
      mock.rides['ride_c'] = {
        'id': 'ride_c',
        'status': 'cancelledByRider',
        'version': 3,
        'updatedAt': '2026-11-02T09:00:00.000Z',
        'categoryId': 'economy',
        'paymentMethodId': 'cash',
        'price': 120,
        'pickupAddress': 'A',
        'pickupLat': 59.33,
        'pickupLng': 18.06,
        'destinationAddress': 'B',
        'destinationLat': 59.34,
        'destinationLng': 18.07,
      };
      final history = await ApiRideHistoryRepository(
        api: ApiClient(client: mock, env: demo),
      ).loadOnDemand();
      expect(history.single.status, ReservationStatus.cancelled);
    });
  });

  group('P2-M2 the finish screen after a reload uses the trip currency', () {
    test('a French trip not in memory gets EUR from the server', () async {
      final controller = RideCompleteController(
        serverCurrency: (id) async => id == 'trip-fr' ? 'EUR' : null,
      );
      expect(await controller.tripCurrency('trip-fr'), 'EUR');
      // Read once, then known: the first tips shown are in euro.
      final tips = controller.initialTips(rideId: 'trip-fr');
      expect(tips, isNotEmpty);
      expect(tips.every((t) => t.currency == 'EUR'), isTrue);
    });
  });

  group('M-1 an old unpaid fee is its own line in the price', () {
    test('fareLines.outstanding_fee is read from the quote', () {
      final quote = ApiQuoteRepository.contractQuoteOf({
        'quoteId': 'q1',
        'categoryId': 'economy',
        'total': {'amountMinor': 17200, 'currency': 'SEK'},
        'expiresAt': '2026-11-02T10:00:00Z',
        'fareLines': [
          {
            'code': 'base',
            'amount': {'amountMinor': 13700, 'currency': 'SEK'},
          },
          {
            'code': 'outstanding_fee',
            'amount': {'amountMinor': 3500, 'currency': 'SEK'},
          },
        ],
      })!;
      expect(quote.outstandingFeeMinor, 3500);
      expect(quote.totalMinor, 17200);
      expect(
        L10n.current.priceIncludesUnpaidFee('35 kr'),
        'Includes 35 kr unpaid fee from an earlier trip',
      );
    });
  });

  group('G16-1 a paused account', () {
    test('sign-in says the account is paused', () {
      const error = ApiError(
        code: 'forbidden',
        message: 'This account is suspended.',
        statusCode: 403,
        reason: 'account_suspended',
      );
      expect(isAccountSuspended(error), isTrue);
      expect(
        authErrorMessage(error, AuthAction.verifyCode),
        L10n.current.accountSuspended,
      );
      L10n.use('sv');
      expect(
        authErrorMessage(error, AuthAction.verifyCode),
        'Ditt Movera-konto är pausat. Kontakta Movera support om du har frågor.',
      );
    });
  });

  group('P2-M6 / P2-L1 route change answers', () {
    test('a reached stop has its own message; a server answer is not '
        '"network"', () {
      expect(
        const RouteChangeException(RouteChangeFailure.visitedStop).message,
        L10n.current.routeVisitedStopLocked,
      );
      expect(
        const RouteChangeException(RouteChangeFailure.refused).message,
        isNot(L10n.current.routeUpdateFailed),
      );
      expect(L10n.current.g7RouteExpired, contains('did not answer in time'));
    });
  });

  group('search steps from the admin', () {
    test('the projection\'s searchStep reaches the event', () {
      final event = RideRealtimeEvent(
        rideId: 't1',
        status: RideStatus.findingDriver,
        sequence: 4,
        payload: {
          searchStepKey: {
            'id': 'step-2',
            'kind': 'keep_waiting',
            'message': 'Det tar lite längre tid. Vill du vänta?',
            'extraMin': 3,
            'at': '2026-11-02T09:00:00Z',
          },
          headingCheckKey: {
            'heading': false,
            'checkedAt': '2026-11-02T09:00:00Z',
            'freeCancel': true,
          },
        },
      );
      final step = event.searchStep!;
      expect(step.asksKeepWaiting, isTrue);
      expect(step.message, 'Det tar lite längre tid. Vill du vänta?');
      expect(step.extraMin, 3);
      expect(event.headingFreeCancel, isTrue);
    });
  });

  group('M-11 receipt in History', () {
    testWidgets('the server receipt total shows under Receipt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ServerReceiptLines(
              rideId: 'trip-1',
              showTotal: true,
              showEndedEarly: false,
              loader: (_) async => ServerReceipt.tryParse({
                'tripId': 'trip-1',
                'total': {'amountMinor': 27700, 'currency': 'SEK'},
                'tip': {
                  'amount': {'amountMinor': 2000, 'currency': 'SEK'},
                },
              }),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('receipt-heading')), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-total')), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-tip')), findsOneWidget);
    });
  });

  group('"Need help?" uses the admin\'s support contact', () {
    test('LegalTexts keeps the company the server sends', () {
      final texts = LegalTexts.fromJson({
        'country': 'SE',
        'version': 3,
        'reaccept': false,
        'terms': {
          'title': {'sv': 'V', 'fr': 'C', 'en': 'T'},
          'text': {'sv': 'v', 'fr': 'c', 'en': 't'},
        },
        'privacy': {
          'title': {'sv': 'I', 'fr': 'P', 'en': 'P'},
          'text': {'sv': 'i', 'fr': 'p', 'en': 'p'},
        },
        'company': {
          'companyName': 'Movera AB',
          'supportEmail': 'help@movera.invalid',
          'supportPhone': '+46 8 000 00 00',
        },
      })!;
      final details = SupportDetails.fromLegalCompany(texts.company);
      expect(details.email, 'help@movera.invalid');
      expect(details.phone, '+46 8 000 00 00');
      expect(details.company, 'Movera AB');
    });

    testWidgets('the box shows the served details', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NeedHelpLink(
              served: () => const SupportDetails(
                email: 'help@movera.invalid',
                phone: '+33 1 00 00 00 00',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('auth-need-help')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-need-help-soon')), findsNothing);
      expect(find.text('help@movera.invalid'), findsOneWidget);
      expect(find.text('+33 1 00 00 00 00'), findsOneWidget);
    });
  });

  group('the rider app follows the account language', () {
    test('no pick on this phone: the account\'s French wins and is not '
        'overwritten', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return json({
          'riderId': 'r1',
          'firstName': 'Anne',
          'language': 'fr',
          'version': 2,
        });
      });
      final language = AppLanguageController(
        store: MemoryAppLanguageStore(),
        deviceLanguage: () => 'sv',
        deviceRegion: () => 'SE',
      );
      final profile = ProfileController(
        store: SyncedProfileRepository(
          api: ApiClient(client: client, env: live),
        ),
      );
      await profile.hydrateWithLanguage(language);
      expect(language.code, 'fr');
      expect(sent.where((r) => r.method == 'PATCH'), isEmpty);
    });
  });
}
