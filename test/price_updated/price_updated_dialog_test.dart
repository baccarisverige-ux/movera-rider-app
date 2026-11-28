// v0.18.174 (contract.json#priceChangeAsk; owner 2026-11-28 "When price more
// allways show", "No popup, book lower", FINAL design v8): the rise-only rule
// and the shared v8 popup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/core/widgets/price_updated_dialog.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  group('priceChangeNeedsAsk (no tolerance)', () {
    const agreed = Money(7930, 'EUR');
    test('a drop 79,30 -> 79,20 € books silently', () {
      expect(priceChangeNeedsAsk(agreed, const Money(7920, 'EUR')), isFalse);
    });
    test('the same price books', () {
      expect(priceChangeNeedsAsk(agreed, const Money(7930, 'EUR')), isFalse);
    });
    test('+1 cent asks', () {
      expect(priceChangeNeedsAsk(agreed, const Money(7931, 'EUR')), isTrue);
    });
    test('+2,20 € asks', () {
      expect(priceChangeNeedsAsk(agreed, const Money(8150, 'EUR')), isTrue);
    });
    test('another currency always asks', () {
      expect(priceChangeNeedsAsk(agreed, const Money(100, 'SEK')), isTrue);
    });
  });

  group('v0.18.174 request fields and the 409 answer', () {
    Map<String, dynamic> body({String? agreed, bool accepted = false}) =>
        BookingCoordinator.contractTripBody(
          quoteId: 'qte_1',
          categoryId: 'economy',
          paymentMethod: 'cash',
          pickupLat: 48.85,
          pickupLng: 2.35,
          destinationLat: 49.31,
          destinationLng: 2.35,
          agreedQuoteId: agreed,
          priceAccepted: accepted,
        );
    test('POST /trips carries agreedQuoteId, and priceAccepted only when '
        'the rider accepted a higher price', () {
      expect(body(agreed: 'qte_0')['agreedQuoteId'], 'qte_0');
      expect(body(agreed: 'qte_0').containsKey('priceAccepted'), isFalse);
      expect(body(agreed: 'qte_0', accepted: true)['priceAccepted'], isTrue);
      expect(body().containsKey('agreedQuoteId'), isFalse);
      expect(body(accepted: true).containsKey('priceAccepted'), isFalse);
      for (final money in ['total', 'fareMinor', 'price', 'totalMinor']) {
        expect(body(agreed: 'qte_0').containsKey(money), isFalse);
      }
    });
    test('booked rides (POST /trips, /reschedule) carry the same fields', () {
      expect(ApiReservationRepository.priceChangeAskBody('qte_0', true), {
        'agreedQuoteId': 'qte_0',
        'priceAccepted': true,
      });
      expect(ApiReservationRepository.priceChangeAskBody('qte_0', false), {
        'agreedQuoteId': 'qte_0',
      });
      expect(ApiReservationRepository.priceChangeAskBody(null, true), isEmpty);
    });
    test("409 price_changed_ask gives the server's fresh price", () {
      const ask = ApiError(
        code: 'conflict',
        message: 'up',
        statusCode: 409,
        reason: 'price_changed_ask',
        details: ['fresh:8150 EUR', 'agreed:7930 EUR'],
      );
      expect(isPriceChangedAsk(ask), isTrue);
      expect(priceChangedAskFresh(ask), const Money(8150, 'EUR'));
      const other = ApiError(
        code: 'conflict',
        message: 'x',
        reason: 'quote_used',
      );
      expect(isPriceChangedAsk(other), isFalse);
      expect(priceChangedAskFresh(other), isNull);
    });
  });

  Future<Future<bool>> open(
    WidgetTester tester, {
    required String lang,
    required String category,
    required Money price,
  }) async {
    L10n.use(lang);
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => result = PriceUpdatedDialog.show(
                context,
                categoryName: category,
                price: formatMoney(price),
                keyPrefix: 'select-ride',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('v8 FR: ↻ + "Prix recalculé", one grey line, the price only in '
      'the black button "Réserver Premium · 81,50 €", ✕, no old price, no '
      'divider, no Pas maintenant', (tester) async {
    await open(
      tester,
      lang: 'fr',
      category: 'Premium',
      price: const Money(8150, 'EUR'),
    );
    final dialog = find.byKey(const ValueKey('select-ride-price-updated'));
    expect(dialog, findsOneWidget);
    expect(find.text('Prix recalculé'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(
      tester.getSize(find.byIcon(Icons.refresh_rounded)).width,
      lessThanOrEqualTo(24),
    );
    expect(
      find.text(
        'Mis à jour selon votre point de prise en charge et le trafic actuel.',
      ),
      findsOneWidget,
    );
    final buttonText = find.text(
      'Réserver Premium · ${formatMoney(const Money(8150, 'EUR'))}',
    );
    expect(buttonText, findsOneWidget);
    expect(formatMoney(const Money(8150, 'EUR')), contains('81,50'));
    // The price is shown only once (in the button).
    expect(find.textContaining('81,50'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('select-ride-price-close')),
      findsOneWidget,
    );
    expect(find.text('Pas maintenant'), findsNothing);
    expect(find.text('Prix mis à jour'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('select-ride-price-accept')),
    );
    expect(
      button.style!.backgroundColor!.resolve(<WidgetState>{}),
      const Color(0xFF000000),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('select-ride-price-accept')))
          .height,
      52,
    );
    expect(
      tester.widget<Dialog>(dialog).backgroundColor,
      const Color(0xFFFFFFFF),
    );
    // Black and white only: no Material blue anywhere in the popup.
    for (final text in tester.widgetList<Text>(
      find.descendant(of: dialog, matching: find.byType(Text)),
    )) {
      final color = text.style?.color;
      expect(
        color == null || color.b <= color.r + 0.01,
        isTrue,
        reason: '${text.data} $color',
      );
    }
  });

  testWidgets('v8 SV: "Boka Movera · 815 kr" (exact öre kept)', (tester) async {
    await open(
      tester,
      lang: 'sv',
      category: 'Movera',
      price: const Money(81500, 'SEK'),
    );
    expect(find.text('Priset har räknats om'), findsOneWidget);
    expect(
      find.text('Uppdaterat efter din upphämtningsplats och aktuell trafik.'),
      findsOneWidget,
    );
    expect(
      find.text('Boka Movera · ${formatMoney(const Money(81500, 'SEK'))}'),
      findsOneWidget,
    );
  });

  testWidgets('the button returns true, ✕ returns false', (tester) async {
    var result = await open(
      tester,
      lang: 'en',
      category: 'Movera',
      price: const Money(8150, 'EUR'),
    );
    expect(find.textContaining('Book Movera · '), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-ride-price-accept')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    result = await open(
      tester,
      lang: 'en',
      category: 'Movera',
      price: const Money(8150, 'EUR'),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label == 'Close'),
      hasLength(1),
    );
    await tester.tap(find.byKey(const ValueKey('select-ride-price-close')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
