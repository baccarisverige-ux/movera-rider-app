import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/phone_country_picker.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';
import 'package:movera_rider/shared/widgets/country_flag.dart';

/// Owner 2026-11-03, decisions/servers-test-live.md "Load time" LT-3: small
/// flag pictures instead of emoji flags (the emoji showed as a box on first
/// paint, and the web app would download a 700 kB emoji font to draw them).
bool _hasFlagEmoji(String text) =>
    text.runes.any((r) => r >= 0x1F1E6 && r <= 0x1F1FF);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('every country of the phone field has a flag picture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(PhoneCountries.all.length, greaterThan(200));
    for (final country in PhoneCountries.all) {
      final data = await rootBundle.load(CountryFlag.assetOf(country.iso));
      expect(data.lengthInBytes, greaterThan(50), reason: country.iso);
    }
  });

  testWidgets('the sign-in phone field shows the flag picture, no emoji', (
    tester,
  ) async {
    for (final country in [
      PhoneCountries.sweden,
      PhoneCountries.france,
      PhoneCountries.tunisia,
    ]) {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          AuthPhoneField(
            controller: controller,
            focusNode: focus,
            country: country,
            onCountryChanged: (_) {},
          ),
        ),
      );
      final flag = find.byKey(ValueKey('country-flag-${country.iso}'));
      expect(flag, findsOneWidget);
      expect(
        (tester.widget<Image>(flag).image as AssetImage).assetName,
        'assets/flags/${country.iso.toLowerCase()}.png',
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(_hasFlagEmoji(text.data ?? ''), isFalse);
      }
    }
  });

  testWidgets('the country sheet lists flag pictures', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(PhoneCountrySheet(selected: PhoneCountries.sweden)),
    );
    await tester.pump();
    expect(find.byType(CountryFlag), findsWidgets);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(_hasFlagEmoji(text.data ?? ''), isFalse);
    }
  });

  testWidgets('a code without a picture shows its letters', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CountryFlag('ZZ'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ZZ'), findsOneWidget);
  });
}
