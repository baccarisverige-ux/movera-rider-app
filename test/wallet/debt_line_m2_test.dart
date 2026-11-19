// Debt line M2 (owner 2026-11-19, button "Yes, build M2 + M3 (Rec.)";
// Q-M1 "as its own line"). Rider Sara owes 35 kr from a late cancel and
// rides for 215 kr: her screen said only "Betala i bilen · 215,00 kr"
// while the driver was told to take 250 kr. Now the 215 kr line stays as
// it is and a row under it says "+ 35,00 kr obetald avgift från tidigare
// resa" and "Att betala 250,00 kr". Display only: no amount changes.
//
// Fail-before on main 41919f46: no `trip-debt-box` exists.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/wallet/presentation/trip_debt_box.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _noop() {}

const _box = ValueKey<String>('trip-debt-box');
const _line = ValueKey<String>('trip-debt-line');
const _total = ValueKey<String>('trip-debt-total');
const _summary = ValueKey<String>('trip-summary-line');

/// A non-breaking space, as the amounts are written (never split in two).
const _nb = ' ';

/// The server answers a debt read with [owed].
void _serverOwes(List<Money> owed) {
  RiderOutstanding.refresher = () async {
    RiderOutstanding.current.value = RiderOutstanding(byCurrency: owed);
    return true;
  };
}

Widget _inTrip({
  double price = 215,
  String currency = 'SEK',
  int walletMinor = 0,
  String paymentMethod = 'cash',
  RideStatus status = RideStatus.tripInProgress,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RiderInTripPanel(
        destinationAddress: 'Gullmarsplan, Johanneshov',
        rideType: 'Movera',
        paymentMethod: paymentMethod,
        walletAmountMinor: walletMinor,
        price: price,
        currency: currency,
        driver: null,
        rideId: 'ride-m2',
        status: status,
        onOpenProfile: _noop,
        onCall: _noop,
        onCancel: _noop,
      ),
    ),
  ),
);

Widget _waiting({double price = 215, String currency = 'SEK'}) => MaterialApp(
  home: Scaffold(
    body: WaitingRideDetailsCard(
      rideType: 'Movera',
      pickupAddress: 'Sveavägen 1, Stockholm',
      paymentMethod: 'cash',
      price: price,
      currency: currency,
    ),
  ),
);

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void _phone(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    L10n.use('sv');
    RiderOutstanding.reset();
    RiderOutstanding.refresher = null;
  });
  tearDown(() {
    L10n.use('en');
    RiderOutstanding.reset();
    RiderOutstanding.refresher = null;
  });

  group('on board (the approved picture M2)', () {
    testWidgets('215 kr line untouched, + 35 kr row, to pay 250 kr', (
      tester,
    ) async {
      // What the screen said before any debt row existed.
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      final before = _text(tester, _summary);
      expect(before, 'Movera · Betala i bilen · 215,00 kr');
      expect(find.byKey(_box), findsNothing);

      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();

      expect(_text(tester, _summary), before);
      expect(
        _text(tester, _line),
        '+ 35,00${_nb}kr obetald avgift från tidigare resa',
      );
      expect(find.text('Att betala'), findsOneWidget);
      expect(_text(tester, _total), '250,00${_nb}kr');
      // Under the payment line, above the driver card.
      expect(
        tester.getTopLeft(find.byKey(_box)).dy,
        greaterThan(tester.getBottomLeft(find.byKey(_summary)).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no debt: the screen is exactly as before', (tester) async {
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      final height = tester.getSize(find.byType(RiderInTripPanel)).height;
      final summaryBottom = tester.getBottomLeft(find.byKey(_summary)).dy;
      final cardTop = tester.getTopLeft(find.byType(WaitingDriverCard)).dy;

      _serverOwes(const []);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();

      expect(find.byKey(_box), findsNothing);
      expect(find.text('Att betala'), findsNothing);
      expect(tester.getSize(find.byType(RiderInTripPanel)).height, height);
      // The gap between the payment line and the driver card is the old
      // 14 px: the absent row takes no room.
      expect(cardTop - summaryBottom, 14);
      expect(
        tester.getTopLeft(find.byType(WaitingDriverCard)).dy -
            tester.getBottomLeft(find.byKey(_summary)).dy,
        14,
      );
    });

    testWidgets('a debt in another currency is not shown', (tester) async {
      _serverOwes(const [Money(350, 'EUR'), Money(2500, 'TND')]);
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing);
      expect(_text(tester, _summary), 'Movera · Betala i bilen · 215,00 kr');
    });

    testWidgets('only the trip currency of several debts is added', (
      tester,
    ) async {
      _serverOwes(const [Money(350, 'EUR'), Money(3500, 'SEK')]);
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(_text(tester, _total), '250,00${_nb}kr');
    });

    testWidgets('an old debt kept in the app is not shown until the server '
        'answers', (tester) async {
      // Read at sign-in, maybe paid since: not trusted for this row.
      RiderOutstanding.current.value = const RiderOutstanding(
        byCurrency: [Money(3500, 'SEK')],
      );
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing, reason: 'no reader at all');

      RiderOutstanding.refresher = () async => false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing, reason: 'the read failed');

      RiderOutstanding.refresher = () async => throw StateError('offline');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing, reason: 'the read threw');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wallet pays a part: no row (a wallet with money has '
        'no debt)', (tester) async {
      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(_inTrip(walletMinor: 5000));
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing);
    });

    testWidgets('the debt is read again at each stage and the row follows '
        'it', (tester) async {
      var reads = 0;
      var owed = const [Money(3500, 'SEK')];
      RiderOutstanding.refresher = () async {
        reads++;
        RiderOutstanding.current.value = RiderOutstanding(byCurrency: owed);
        return true;
      };
      await tester.pumpWidget(_inTrip(status: RideStatus.tripStarted));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(_text(tester, _total), '250,00${_nb}kr');

      // An admin removed the fee during the ride.
      owed = const [];
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byKey(_box), findsNothing);
    });

    testWidgets('the price changed on the way: the total follows the line '
        'above', (tester) async {
      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(_inTrip(price: 229.5));
      await tester.pumpAndSettle();
      expect(_text(tester, _summary), 'Movera · Betala i bilen · 229,50 kr');
      expect(_text(tester, _total), '264,50${_nb}kr');
    });
  });

  group('money format', () {
    testWidgets('dinars keep three decimals', (tester) async {
      _serverOwes(const [Money(2500, 'TND')]);
      await tester.pumpWidget(_inTrip(price: 12.35, currency: 'TND'));
      await tester.pumpAndSettle();
      expect(_text(tester, _line), startsWith('+ 2.500${_nb}DT '));
      expect(_text(tester, _total), '14.850${_nb}DT');
    });

    testWidgets('euros', (tester) async {
      L10n.use('fr');
      _serverOwes(const [Money(350, 'EUR')]);
      await tester.pumpWidget(_inTrip(price: 21.5, currency: 'EUR'));
      await tester.pumpAndSettle();
      expect(
        _text(tester, _line),
        '+ 3,50$_nb€ de frais impayés d’un trajet précédent',
      );
      expect(find.text('À payer'), findsOneWidget);
      expect(_text(tester, _total), '25,00$_nb€');
    });

    testWidgets('English', (tester) async {
      L10n.use('en');
      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(_inTrip());
      await tester.pumpAndSettle();
      expect(
        _text(tester, _line),
        '+ 35,00${_nb}kr unpaid fee from an earlier trip',
      );
      expect(find.text('To pay'), findsOneWidget);
    });
  });

  group('320 px and long amounts', () {
    for (final lang in const ['sv', 'fr', 'en']) {
      testWidgets('whole text, no overflow ($lang)', (tester) async {
        L10n.use(lang);
        _phone(tester, 320);
        _serverOwes(const [Money(125000, 'SEK')]);
        await tester.pumpWidget(_inTrip(price: 12345.5));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_text(tester, _total), '13${_nb}595,50${_nb}kr');
        final paragraphs = find.descendant(
          of: find.byKey(_box),
          matching: find.byType(RichText),
        );
        for (final element in paragraphs.evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        // The amount to pay stays on one line, inside the box.
        final box = tester.getRect(find.byKey(_box));
        final total = tester.getRect(find.byKey(_total));
        expect(total.right, lessThanOrEqualTo(box.right));
        expect(total.height, lessThan(30));
        expect(box.right, lessThanOrEqualTo(320));
      });
    }
  });

  group('before the ride starts: the same row', () {
    testWidgets('waiting for the driver', (tester) async {
      await tester.pumpWidget(_waiting());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsNothing);
      final before = find.text('Betala i bilen · 215,00 kr');
      expect(before, findsOneWidget);

      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_waiting());
      await tester.pumpAndSettle();
      expect(find.text('Betala i bilen · 215,00 kr'), findsOneWidget);
      expect(_text(tester, _total), '250,00${_nb}kr');
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting, 320 px', (tester) async {
      _phone(tester, 320);
      _serverOwes(const [Money(3500, 'SEK')]);
      await tester.pumpWidget(_waiting());
      await tester.pumpAndSettle();
      expect(find.byKey(_box), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the box alone', () {
    testWidgets('to pay = the price on the line + the debt, to the minor '
        'unit', (tester) async {
      _serverOwes(const [Money(1, 'SEK')]);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TripDebtBox(priceKr: 0.99, currency: 'SEK')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, _total), '1,00${_nb}kr');
    });
  });

  group('the debt read (GET /rider/profile)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    const env = AppEnv(
      flavor: AppFlavor.test,
      apiBaseUrl: 'https://api.test.movera.invalid',
    );
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    Map<String, dynamic> rider(List<Map<String, Object>> owed) => {
      'riderId': 'rdr_1',
      'firstName': 'Sara',
      'status': 'active',
      'version': 3,
      'language': 'sv',
      'consents': {'rideUpdates': true},
      'outstandingByCurrency': owed,
    };

    test('takes the debt the server says now, and only reads', () async {
      final methods = <String>[];
      var owed = <Map<String, Object>>[];
      final repo = SyncedProfileRepository(
        api: ApiClient(
          env: env,
          tokens: MemoryTokenStore(),
          client: MockClient((request) async {
            methods.add(request.method);
            return json(rider(owed));
          }),
        ),
      );
      await repo.hydrate();
      expect(RiderOutstanding.current.value.owesAnything, isFalse);

      // A late-cancel fee after sign-in: the app's copy is old.
      owed = [
        {'amountMinor': 3500, 'currency': 'SEK'},
      ];
      expect(await repo.refreshOutstanding(), isTrue);
      expect(
        RiderOutstanding.current.value.inCurrency('SEK')?.amountMinor,
        3500,
      );
      expect(repo.current.name, 'Sara');
      expect(methods, everyElement('GET'));
    });

    test('a failed read answers false and changes nothing', () async {
      var fail = false;
      final repo = SyncedProfileRepository(
        api: ApiClient(
          env: env,
          tokens: MemoryTokenStore(),
          client: MockClient((request) async {
            if (fail) return json({'code': 'internal'}, 500);
            return json(
              rider([
                {'amountMinor': 3500, 'currency': 'SEK'},
              ]),
            );
          }),
        ),
      );
      await repo.hydrate();
      fail = true;
      expect(await repo.refreshOutstanding(), isFalse);
      expect(
        RiderOutstanding.current.value.inCurrency('SEK')?.amountMinor,
        3500,
      );
    });

    test('an answer for a rider who signed out is dropped', () async {
      late SyncedProfileRepository repo;
      repo = SyncedProfileRepository(
        api: ApiClient(
          env: env,
          tokens: MemoryTokenStore(),
          client: MockClient((request) async {
            repo.clearLocal();
            return json(
              rider([
                {'amountMinor': 3500, 'currency': 'SEK'},
              ]),
            );
          }),
        ),
      );
      expect(await repo.refreshOutstanding(), isFalse);
      expect(RiderOutstanding.current.value.owesAnything, isFalse);
    });
  });
}
