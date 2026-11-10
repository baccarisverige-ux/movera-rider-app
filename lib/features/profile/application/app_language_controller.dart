import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/profile/data/app_language_store.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The app's language (owner Q48/Q49).
///
/// The rider's own choice (globe button on Sign in, or Account) wins and
/// is saved on the device. Without one (contract v0.18.2
/// `auth.firstLanguage`, owner 2026-10-30 "Phone language (Recommended)")
/// the app speaks the phone's language when it is sv, fr or en; anything
/// else is English (owner 2026-11-10: a French phone in Tunis opened in
/// Swedish). Only a zone that does not offer English falls back to its
/// config's `languages.rider`.
class AppLanguageController extends ChangeNotifier with WidgetsBindingObserver {
  AppLanguageController({
    AppLanguageStore? store,
    String? Function()? deviceLanguage,
    // Kept for callers; the region no longer picks the language.
    String? Function()? deviceRegion,
  }) : _store = store ?? const PrefsAppLanguageStore(),
       _deviceLanguage = deviceLanguage ?? _platformLanguage;

  final AppLanguageStore _store;
  final String? Function() _deviceLanguage;

  /// `auth.firstLanguage.countryDefault`.
  static const Map<String, String> countryDefault = {'SE': 'sv', 'FR': 'fr'};

  static String? _platformLanguage() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    } catch (_) {
      return null;
    }
  }

  String? _choice;
  String _zoneDefault = L10n.fallbackCode;
  List<String> _available = [for (final l in L10n.languages) l.code];

  /// The rider's saved choice, or null to follow the zone.
  String? get choice => _choice;

  /// The language the zone's config names for the rider app.
  String get zoneDefault => _zoneDefault;

  /// rider-u153: the languages the zone lets the rider pick
  /// (`languages.available`), of those the app ships, in the app's order.
  List<String> get available => List.unmodifiable(_available);

  /// The phone's language when the app ships it (sv, fr, en), else null.
  String? get phoneLanguage {
    String? raw;
    try {
      raw = _deviceLanguage()?.trim().toLowerCase();
    } catch (_) {
      raw = null;
    }
    return raw != null && L10n.codes.contains(raw) ? raw : null;
  }

  /// The language in use: the rider's choice when the zone offers it, else
  /// the phone's language when the app ships it and the zone offers it,
  /// else the start country's default. A choice the zone does not offer is
  /// kept for zones that do.
  String get code {
    final choice = _choice;
    if (choice != null && _available.contains(choice)) return choice;
    final account = _account;
    if (account != null && _available.contains(account)) return account;
    final phone = phoneLanguage;
    if (phone != null && _available.contains(phone)) return phone;
    return _startDefault;
  }

  String _startDefault = L10n.fallbackCode;

  /// Owner 2026-11-10: without a supported phone language, English; the
  /// zone's default only when the zone does not offer English.
  String _startDefaultFor(RiderZone zone) =>
      _available.contains(L10n.fallbackCode) ? L10n.fallbackCode : _zoneDefault;

  bool _following = false;

  /// Follows the phone's language: on Android the engine can report the
  /// locales only after start, and the phone's settings can change while
  /// the app runs. A saved choice still wins.
  void followDevice() {
    if (_following) return;
    _following = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _apply();

  @override
  void dispose() {
    if (_following) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Locale get locale => Locale(code);

  AppLanguage get language => L10n.languageOf(code);

  /// Reads the saved choice and the zone default of [zone] from [config].
  Future<void> load({
    required RiderConfigRepository config,
    RiderZone? zone,
  }) async {
    try {
      final saved = await _store.read();
      if (saved != null && L10n.codes.contains(saved)) _choice = saved;
    } catch (error) {
      AppLog.warning('language.read_failed', extra: {'error': '$error'});
    }
    await useZone(config: config, zone: zone ?? RiderZones.home);
  }

  /// The default of [zone]'s config document; the choice still wins.
  Future<void> useZone({
    required RiderConfigRepository config,
    required RiderZone zone,
  }) async {
    try {
      final document = await config.forZone(zone.id);
      _zoneDefault = L10n.supported(document.languages.rider);
      final offered = document.languages.available.toSet();
      final available = [
        for (final l in L10n.languages)
          if (offered.contains(l.code)) l.code,
      ];
      _available = available.isEmpty
          ? [for (final l in L10n.languages) l.code]
          : available;
      if (!_available.contains(_zoneDefault)) _available.add(_zoneDefault);
    } catch (error) {
      AppLog.warning('language.zone_failed', extra: {'error': '$error'});
    }
    _startDefault = _startDefaultFor(zone);
    _apply();
  }

  /// The account's language (`Rider.language`) when nothing was picked on
  /// this phone: it wins over the phone's language and the zone default.
  /// Not saved as a choice, so a pick on this phone still wins later.
  void useAccount(String code) {
    if (_choice != null || !L10n.codes.contains(code)) return;
    _account = code;
    _apply();
  }

  String? _account;

  /// Takes [code] as the rider's choice and saves it.
  Future<void> choose(String code) async {
    final next = L10n.supported(code);
    _choice = next;
    _apply();
    try {
      await _store.save(next);
    } catch (error) {
      AppLog.warning('language.save_failed', extra: {'error': '$error'});
    }
  }

  String? _applied;

  void _apply() {
    L10n.use(code);
    if (_applied == code) return;
    _applied = code;
    notifyListeners();
  }
}
