import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/profile/data/app_language_store.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The app's language (owner Q48/Q49).
///
/// The rider's own choice in Account wins and is saved on the device.
/// Without one the app speaks the default of the pickup zone's config
/// (`RiderAppConfig.languages.rider`: Swedish in Sweden, French in France
/// and Tunisia).
class AppLanguageController extends ChangeNotifier {
  AppLanguageController({AppLanguageStore? store})
    : _store = store ?? const PrefsAppLanguageStore();

  final AppLanguageStore _store;

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

  /// The language in use: the rider's choice when the zone offers it, else
  /// the zone's default. A choice the zone does not offer is kept for
  /// zones that do.
  String get code {
    final choice = _choice;
    return choice != null && _available.contains(choice)
        ? choice
        : _zoneDefault;
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
    _apply();
  }

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
