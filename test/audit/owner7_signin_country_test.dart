import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/add_phone.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decision 7: every country in the sign-in phone field, starting in
/// the rider's country, and a language switch on every sign-in screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final se = PhoneCountries.sweden;
  final fr = PhoneCountries.france;
  final tn = PhoneCountries.tunisia;
  final de = PhoneCountries.byIso('DE')!;
  final us = PhoneCountries.byIso('US')!;

  test('the number check: E.164 per country, trunk 0 dropped', () {
    final table = <(String, PhoneCountry, String?)>[
      ('70 123 45 67', se, '+46701234567'),
      ('070 123 45 67', se, '+46701234567'),
      ('08 123 456 78', se, null), // Swedish landline
      ('6 12 34 56 78', fr, '+33612345678'),
      ('07 12 34 56 78', fr, '+33712345678'),
      ('01 23 45 67 89', fr, null), // French landline
      ('6 12 34 56 7', fr, null), // a digit short
      ('20 123 456', tn, '+21620123456'),
      ('98 765 432', tn, '+21698765432'),
      ('71 123 456', tn, null), // Tunis landline
      ('0151 2345 6789', de, '+4915123456789'),
      ('415 555 0123', us, '+14155550123'),
      ('123', de, null), // too short
      ('123456789012345', de, null), // too long
      ('+33 6 12 34 56 78', se, '+33612345678'), // pasted, another country
      ('0046 70 123 45 67', fr, '+46701234567'),
    ];
    for (final (typed, country, expected) in table) {
      expect(
        phoneNumberFromField(typed, country),
        expected,
        reason: '$typed in ${country.iso}',
      );
    }
  });

  test('the starting country: saved fix, else last zone, else device, else '
      'Sweden; only Sweden or France (v0.18.2 auth.startCountry)', () {
    // A last fix in Paris.
    expect(PhoneCountries.defaultFor(lastFixLat: 48.85, lastFixLng: 2.35), fr);
    // A fix outside every zone: the device's region, not the home zone;
    // a German phone is not a start country (owner 2026-10-30), so Sweden.
    expect(
      PhoneCountries.defaultFor(
        lastFixLat: 52.5,
        lastFixLng: 13.4,
        lastZone: RiderZones.sweden,
        localeRegion: 'DE',
      ),
      se,
    );
    expect(
      PhoneCountries.defaultFor(
        lastFixLat: 52.5,
        lastFixLng: 13.4,
        lastZone: RiderZones.sweden,
        localeRegion: 'FR',
      ),
      fr,
    );
    // The Tunisia zone is skipped; the device's Swedish region is next.
    expect(
      PhoneCountries.defaultFor(
        lastZone: RiderZones.tunisia,
        localeRegion: 'SE',
      ),
      se,
    );
    expect(PhoneCountries.defaultFor(localeRegion: 'US'), se);
    expect(PhoneCountries.defaultFor(), se);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final language = AppScope.instance.language;
    addTearDown(() => language.choose('en'));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => ListenableBuilder(
          listenable: language,
          builder: (_, __) => MaterialApp(
            locale: language.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // As MoveraApp: a new language redraws every screen.
            builder: (_, page) =>
                LanguageRebuild(code: language.code, child: page!),
            home: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the country sheet finds Tunisie in French and sets +216', (
    tester,
  ) async {
    await AppScope.instance.language.choose('fr');
    var country = se;
    await pump(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (_, setState) => AuthPhoneField(
            controller: TextEditingController(),
            focusNode: FocusNode(),
            country: country,
            onCountryChanged: (c) => setState(() => country = c),
          ),
        ),
      ),
    );
    expect(find.text('+46'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Indicatif : Suède, \\+46')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('auth-phone-country')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-country-search')),
      'tunisie',
    );
    await tester.pump();
    expect(find.text('Tunisie'), findsOneWidget);

    await tester.tap(find.text('Tunisie'));
    await tester.pumpAndSettle();
    expect(country, tn);
    expect(find.text('+216'), findsOneWidget);
  });

  test('the English name and the dial code find it too', () {
    expect(PhoneCountries.search('Tunisia', 'en'), [tn]);
    expect(PhoneCountries.search('+216', 'sv'), [tn]);
  });

  testWidgets('every sign-in screen has the language switch', (tester) async {
    final screens = <Widget>[
      const SignIn(),
      const PhoneVerification(phoneNumber: '+33612345678'),
      const RiderNameScreen(),
      const AddPhoneNumber(
        link: ProviderLink(provider: 'apple', linkToken: 'link'),
      ),
    ];
    for (final screen in screens) {
      await pump(tester, screen);
      expect(
        find.byTooltip('Change language'),
        findsOneWidget,
        reason: '${screen.runtimeType}',
      );
      final size = tester.getSize(find.byKey(const ValueKey('auth-language')));
      expect(size.width >= 48 && size.height >= 48, isTrue);
      // PhoneVerification runs a timer: unmount it.
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('switching to Français changes the screen at once', (
    tester,
  ) async {
    await pump(tester, const SignIn());
    expect(find.text('Enter your phone number'), findsOneWidget);

    await tester.tap(find.byTooltip('Change language'));
    await tester.pumpAndSettle();
    expect(find.text('Svenska'), findsOneWidget);
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(AppScope.instance.language.code, 'fr');
    expect(find.text('Saisissez votre numéro de téléphone'), findsOneWidget);
    expect(find.byTooltip('Changer de langue'), findsOneWidget);
  });
}
