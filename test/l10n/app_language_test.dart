import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/app_language_store.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A config source whose zones name [riderDefault] as the rider language.
class _Config implements RiderConfigRepository {
  _Config(this.byZone);

  final Map<String, String> byZone;

  RiderAppConfig _doc(String zoneId) => RiderAppConfig.fromJson({
    ...SeedRiderConfigRepository.seedDocument,
    'zoneId': zoneId,
    'languages': {
      'available': ['en', 'fr', 'sv'],
      'default': {'rider': byZone[zoneId], 'driver': 'en', 'admin': 'en'},
    },
  })!;

  @override
  Future<RiderAppConfig> current() async => _doc(RiderZones.home.id);

  @override
  Future<RiderAppConfig> forZone(String zoneId) async => _doc(zoneId);
}

/// Round 4 (owner Q48): the pickup zone's config picks the default; the
/// rider's own choice in Account wins and is saved. Since v0.18.2
/// (`auth.firstLanguage`) the phone's language comes first when the app
/// ships it, so these run on a phone in a language it does not ship.
AppLanguageController _controller(AppLanguageStore store) =>
    AppLanguageController(
      store: store,
      deviceLanguage: () => 'de',
      deviceRegion: () => 'FR',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  group('zone default', () {
    const seeds = SeedRiderConfigRepository();

    test('Sweden speaks Swedish, France and Tunisia French', () async {
      for (final (zone, code) in [
        (RiderZones.sweden, 'sv'),
        (RiderZones.france, 'fr'),
        (RiderZones.tunisia, 'fr'),
      ]) {
        final language = _controller(MemoryAppLanguageStore());
        await language.load(config: seeds, zone: zone);
        expect(language.code, code, reason: zone.id);
        expect(language.locale, Locale(code));
        expect(L10n.code, code, reason: 'strings without a context follow');
      }
    });

    test('it is the config document that decides, not the country', () async {
      final config = _Config({RiderZones.sweden.id: 'fr'});
      final language = _controller(MemoryAppLanguageStore());
      await language.load(config: config, zone: RiderZones.sweden);
      expect(language.code, 'fr');
    });

    test('a good fix in another zone moves the default', () async {
      final language = _controller(MemoryAppLanguageStore());
      await language.load(config: seeds, zone: RiderZones.sweden);
      expect(language.code, 'sv');
      var notified = 0;
      language.addListener(() => notified++);
      await language.useZone(config: seeds, zone: RiderZones.france);
      expect(language.code, 'fr');
      expect(notified, 1);
    });
  });

  group('rider choice', () {
    test('overrides the zone default and survives a restart', () async {
      final store = MemoryAppLanguageStore();
      const seeds = SeedRiderConfigRepository();
      final first = _controller(store);
      await first.load(config: seeds, zone: RiderZones.france);
      expect(first.code, 'fr');

      await first.choose('en');
      expect(first.code, 'en');
      expect(store.value, 'en');

      // Next launch, still in France: the saved choice wins.
      final relaunched = _controller(store);
      await relaunched.load(config: seeds, zone: RiderZones.france);
      expect(relaunched.choice, 'en');
      expect(relaunched.code, 'en');
      // Moving zones does not undo the rider's choice either.
      await relaunched.useZone(config: seeds, zone: RiderZones.sweden);
      expect(relaunched.code, 'en');
    });

    test('is kept in SharedPreferences on the device', () async {
      SharedPreferences.setMockInitialValues({});
      const store = PrefsAppLanguageStore();
      final language = _controller(store);
      await language.load(
        config: const SeedRiderConfigRepository(),
        zone: RiderZones.sweden,
      );
      await language.choose('fr');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PrefsAppLanguageStore.key), 'fr');
      expect(await store.read(), 'fr');
    });

    test('an unknown saved code falls back to the zone default', () async {
      final language = _controller(MemoryAppLanguageStore('ar'));
      await language.load(
        config: const SeedRiderConfigRepository(),
        zone: RiderZones.sweden,
      );
      expect(language.choice, isNull);
      expect(language.code, 'sv');
    });

    testWidgets('Account lists FR / SV / EN and switches the app', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryAppLanguageStore();
      final language = _controller(store);
      await language.load(
        config: const SeedRiderConfigRepository(),
        zone: RiderZones.france,
      );
      final profile = ProfileController(
        store: ProfileRepository(storageKey: 'language_test_profile'),
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: language,
          builder: (context, _) => MaterialApp(
            locale: language.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AccountHomePage(controller: profile, language: language),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // France's default: the Account screen is in French.
      expect(find.text('Compte'), findsOneWidget);
      expect(find.text('FR · Français'), findsOneWidget);

      await tester.tap(find.text('Langue'));
      await tester.pumpAndSettle();
      expect(find.text('EN · English'), findsOneWidget);
      expect(find.text('SV · Svenska'), findsOneWidget);
      expect(find.text('FR · Français'), findsWidgets);

      await tester.tap(find.text('SV · Svenska'));
      await tester.pumpAndSettle();
      expect(language.code, 'sv');
      expect(store.value, 'sv');
      expect(profile.profile.language, 'sv');
      expect(find.text('Konto'), findsOneWidget);
      expect(find.text('SV · Svenska'), findsOneWidget);
    });
  });

  testWidgets('a new language reaches screens already open', (tester) async {
    final language = _controller(MemoryAppLanguageStore());
    await language.load(
      config: const SeedRiderConfigRepository(),
      zone: RiderZones.sweden,
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: language,
        builder: (context, _) => MaterialApp(
          navigatorKey: navigator,
          locale: language.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              LanguageRebuild(code: language.code, child: child!),
          home: const _WhereTo(),
        ),
      ),
    );
    // A second screen on top; the first stays open below it.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const _WhereTo()),
    );
    await tester.pumpAndSettle();
    final sv = lookupAppLocalizations(const Locale('sv')).whereTo;
    final fr = lookupAppLocalizations(const Locale('fr')).whereTo;
    expect(find.text(sv, skipOffstage: false), findsNWidgets(2));

    await language.choose('fr');
    await tester.pumpAndSettle();
    expect(find.text(fr, skipOffstage: false), findsNWidgets(2));
    expect(find.text(sv, skipOffstage: false), findsNothing);
  });

  test('dates follow the chosen language; times stay 24-hour', () {
    final when = DateTime(2026, 10, 5, 8, 5);
    L10n.use('en');
    expect(L10n.formatDate(when, 'd MMM yyyy'), '5 Oct 2026');
    L10n.use('fr');
    expect(L10n.formatDate(when, 'd MMM yyyy'), '5 oct. 2026');
    expect(L10n.formatDate(when, 'MMMM'), 'octobre');
    L10n.use('sv');
    expect(L10n.formatDate(when, 'MMMM'), 'oktober');
    expect(L10n.formatTime(when), '08:05');
  });
}

/// A const screen: only [LanguageRebuild] can make it show a new language.
class _WhereTo extends StatelessWidget {
  const _WhereTo();

  @override
  Widget build(BuildContext context) => Text(context.l10n.whereTo);
}
