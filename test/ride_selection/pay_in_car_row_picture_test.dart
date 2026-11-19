// Owner 2026-11-19: on Choose your ride, the pay-in-car payment row shows the
// picture S2 (banknote, card and phone) straight on the white row, in place
// of the small green tile with a car. Only the picture changes: the row's
// two texts, its arrow, its height and where the texts sit stay as they
// were, at 320 and 390 pt, in en, sv and fr.
//
// Fail-before on main f622cdbc: the row has no S2 picture (it shows the
// green tile with the car icon).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

const _texts = <String, (String, String)>{
  'en': ('Pay in car', 'Pay the driver in the car when the trip ends.'),
  'sv': ('Betala i bilen', 'Betala föraren i bilen när resan är klar.'),
  'fr': ('Payer à bord', 'Payez le chauffeur à bord à la fin de la course.'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  for (final lang in const ['en', 'sv', 'fr']) {
    for (final width in const [320.0, 390.0]) {
      testWidgets('pay-in-car row shows picture S2, texts and layout '
          'unchanged ($lang, ${width.toInt()} pt)', (tester) async {
        L10n.use(lang);
        SharedPreferences.setMockInitialValues({});
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await pumpMoveraScreen(
            tester,
            const SelectRide(
              pickupAddress: 'Pickup',
              destinationAddress: 'Destination',
              pickupPosition: LatLng(59.3293, 18.0686),
              destinationPosition: LatLng(59.3429, 18.0496),
            ),
            viewport: Size(width, 844),
            locale: Locale(lang),
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          _check(tester, lang);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
          debugDefaultTargetPlatformOverride = null;
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}

void _check(WidgetTester tester, String lang) {
  final row = find.byKey(const ValueKey('select-ride-payment'));
  expect(row, findsOneWidget);

  // The new picture: the S2 asset, 50 x 50, no tile behind it.
  final picture = find.descendant(
    of: row,
    matching: find.byKey(const ValueKey('select-ride-pay-in-car-picture')),
  );
  expect(picture, findsOneWidget);
  final image = tester.widget<Image>(picture);
  expect(
    (image.image as AssetImage).assetName,
    'assets/images/pay_in_car_s2.png',
  );
  expect(tester.getSize(picture), const Size(50, 50));
  expect(
    find.descendant(
      of: row,
      matching: find.byIcon(Icons.directions_car_filled_outlined),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: row, matching: find.byType(DecoratedBox)),
    findsNothing,
    reason: 'no box behind the picture',
  );

  // Texts: the same two lines, whole, and the same arrow.
  final (title, line) = _texts[lang]!;
  final titleText = find.descendant(of: row, matching: find.text(title));
  final lineText = find.descendant(of: row, matching: find.text(line));
  expect(titleText, findsOneWidget);
  expect(lineText, findsOneWidget);
  expect(
    find.descendant(
      of: row,
      matching: find.byIcon(Icons.chevron_right_rounded),
    ),
    findsOneWidget,
  );
  // Layout as before the change: the row is 52 high and the texts
  // start 58 from its left edge (4 + the old 42 tile + 12).
  final rowRect = tester.getRect(row);
  expect(rowRect.height, 52);
  expect(tester.getTopLeft(titleText).dx - rowRect.left, 58);
  expect(tester.getTopLeft(lineText).dx - rowRect.left, 58);
  // ... and they still end before the arrow (22 wide, 2 from the right).
  final arrow = tester.getRect(
    find.descendant(
      of: row,
      matching: find.byIcon(Icons.chevron_right_rounded),
    ),
  );
  expect(rowRect.right - arrow.right, 2);
  expect(tester.getRect(titleText).right, lessThanOrEqualTo(arrow.left));
  expect(tester.getRect(lineText).right, lessThanOrEqualTo(arrow.left));

  // The picture stays inside the row and off the texts.
  final pictureRect = tester.getRect(picture);
  expect(pictureRect.left, greaterThanOrEqualTo(rowRect.left));
  expect(pictureRect.top, greaterThanOrEqualTo(rowRect.top));
  expect(pictureRect.bottom, lessThanOrEqualTo(rowRect.bottom));
  expect(pictureRect.right, lessThanOrEqualTo(tester.getTopLeft(titleText).dx));

  // Screen readers: the picture adds no spoken text.
  expect(image.excludeFromSemantics, isTrue);
}
