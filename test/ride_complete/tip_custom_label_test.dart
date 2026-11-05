import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Live G8 round 3 item 4: the "Other amount" tip chip's screen-reader name
/// read "Pourboire de Autre montant". It is a natural phrase in sv, fr and en.
class _CustomAllowed extends RideCompleteController {
  @override
  Future<TipRules> tipRules({String? rideId}) async =>
      const TipRules(customAmount: true, customMax: Money(20000, 'SEK'));
}

/// Job 3 (L12, rider side): a France zone's custom tip.
class _CustomEuro extends RideCompleteController {
  @override
  Future<TipRules> tipRules({String? rideId}) async =>
      const TipRules(customAmount: true, customMax: Money(2000, 'EUR'));

  @override
  Future<List<Money>> tips({String? rideId}) async => const [
    Money(200, 'EUR'),
    Money(500, 'EUR'),
  ];
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const expected = {
    'en': 'Tip: other amount',
    'fr': 'Pourboire : autre montant',
    'sv': 'Dricks: annat belopp',
  };
  for (final entry in expected.entries) {
    testWidgets('Other amount chip is named "${entry.value}" (${entry.key})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      L10n.use(entry.key);
      addTearDown(() => L10n.use('en'));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (_, __) => MaterialApp(
            locale: Locale(entry.key),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: RideCompletedAddTip(controller: _CustomAllowed()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = find.byKey(const ValueKey('tip-custom'));
      expect(chip, findsOneWidget);
      final label = tester.getSemantics(chip).label;
      expect(label, contains(entry.value));
      expect(label, isNot(contains('Pourboire de Autre')));
      semantics.dispose();
    });
  }

  testWidgets('Job 3 / L12: the custom tip field in France ends with €, '
      'not "EUR" or "kr"', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    L10n.use('fr');
    addTearDown(() => L10n.use('en'));
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RideCompletedAddTip(controller: _CustomEuro()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tip-custom')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('tip-custom-field')),
    );
    expect(field.decoration?.suffixText, '€');
  });
}
