import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/ride_selection.dart';

/// Where the list in [RideCatalogController.current] came from.
enum RideCatalogSource { builtIn, cache, server }

/// The rider's ride categories, as the admin panel publishes them.
///
/// `GET /api/v1/ride-types` is the source of truth. The last good answer is
/// cached so a cold start without network still shows yesterday's catalog,
/// and the built-in list is the final fallback. [current] is always
/// readable synchronously; listeners fire when it changes.
class RideCatalogController extends ChangeNotifier {
  RideCatalogController({
    required ApiClient api,
    RideCatalogCache? cache,
    List<RideCatalogItem>? builtIn,
    this.configSource,
  }) : _api = api,
       _cache = cache ?? const PrefsRideCatalogCache(),
       _builtIn = builtIn ?? RideSelectionRepository.builtInRides,
       _current = builtIn ?? RideSelectionRepository.builtInRides;

  static const path = '/api/v1/ride-types';

  /// Owner 2026-10-27: on the contract wire the car types come from the
  /// rider settings the admin publishes (`RiderAppConfig.catalog`), never
  /// from `/ride-types`. The repository keeps the last good document and
  /// falls back to the built-in one, so this always answers.
  final Future<RiderAppConfig> Function()? configSource;

  final ApiClient _api;
  final RideCatalogCache _cache;
  final List<RideCatalogItem> _builtIn;
  List<RideCatalogItem> _current;
  RideCatalogSource _source = RideCatalogSource.builtIn;
  Future<List<RideCatalogItem>>? _inFlight;

  /// The last known catalog; the built-in list until [load] has answered.
  List<RideCatalogItem> get current => _current;

  RideCatalogSource get source => _source;

  /// The current catalog's name for [categoryId] (aliases resolved), or
  /// null when it has no such category.
  String? labelOf(String categoryId) {
    final id = CategoryIds.tryCanonical(categoryId) ?? categoryId;
    for (final item in _current) {
      if ((CategoryIds.tryCanonical(item.id) ?? item.id) == id) {
        return item.name;
      }
    }
    return null;
  }

  /// Asks the server, then the cache, then the built-in list. Never throws;
  /// concurrent calls share one request.
  Future<List<RideCatalogItem>> load() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<List<RideCatalogItem>> _load() async {
    // Audit Phase 4: `/ride-types` is not in the contract and movera-server
    // answers 404, so the contract wire never asks it: there the list is
    // the published rider settings' catalog ([configSource]).
    if (!_api.contractWire) {
      final fromServer = await _loadFromServer();
      if (fromServer != null) return fromServer;
    } else if (configSource != null) {
      final fromConfig = await _loadFromConfig();
      if (fromConfig != null) return fromConfig;
    }
    return _loadFallback();
  }

  Future<List<RideCatalogItem>?> _loadFromServer() async {
    try {
      final response = await _api.get(path);
      final rows = _rowsOf(response);
      final items = RideCatalogJson.parseAll(rows);
      _set(items, RideCatalogSource.server);
      try {
        await _cache.write(rows);
      } catch (error) {
        AppLog.warning(
          'ride_catalog.cache_write_failed',
          extra: {'error': error.toString()},
        );
      }
      return _current;
    } catch (error) {
      AppLog.warning(
        'ride_catalog.fetch_failed',
        extra: {'error': error.toString()},
      );
    }
    return null;
  }

  Future<List<RideCatalogItem>?> _loadFromConfig() async {
    try {
      final config = await configSource!();
      final items = fromConfig(config.categories, _builtIn);
      if (items.isEmpty) return null;
      _set(items, RideCatalogSource.server);
      return _current;
    } catch (error) {
      AppLog.warning(
        'ride_catalog.config_failed',
        extra: {'error': error.toString()},
      );
      return null;
    }
  }

  /// The catalog of a RiderAppConfig: its categories in `sort` order, each
  /// with the admin's label and seats over the built-in item of the same
  /// id (picture, note, list price); a category the app does not know gets
  /// the generic car.
  static List<RideCatalogItem> fromConfig(
    List<RiderConfigCategory> categories,
    List<RideCatalogItem> builtIn,
  ) {
    final sorted = [...categories]..sort((a, b) => a.sort.compareTo(b.sort));
    return [
      for (final category in sorted)
        _withConfig(category, _builtInFor(category.id, builtIn)),
    ];
  }

  static RideCatalogItem? _builtInFor(String id, List<RideCatalogItem> list) {
    for (final item in list) {
      if ((CategoryIds.tryCanonical(item.id) ?? item.id) == id) return item;
    }
    return null;
  }

  static RideCatalogItem _withConfig(
    RiderConfigCategory category,
    RideCatalogItem? known,
  ) => RideCatalogItem(
    id: known?.id ?? category.id,
    image: known?.image ?? RideCatalogJson.fallbackImage,
    name: category.label,
    note: known?.note ?? '',
    arrival: known?.arrival ?? '',
    etaMin: known?.etaMin ?? 0,
    price: known?.price ?? 0,
    seats: category.seats,
    badge: known?.badge,
    glyph: known?.glyph,
    currency: known?.currency ?? 'SEK',
  );

  Future<List<RideCatalogItem>> _loadFallback() async {
    // Only the built-in list is replaced by the cache. A list the server
    // gave earlier in this run is already better than anything cached.
    if (_source == RideCatalogSource.server) return _current;
    try {
      final rows = await _cache.read();
      if (rows != null) {
        final items = RideCatalogJson.parseAll(rows);
        if (items.isNotEmpty) {
          _set(items, RideCatalogSource.cache);
          return _current;
        }
      }
    } catch (error) {
      AppLog.warning(
        'ride_catalog.cache_read_failed',
        extra: {'error': error.toString()},
      );
    }
    _set(_builtIn, RideCatalogSource.builtIn);
    return _current;
  }

  void _set(List<RideCatalogItem> items, RideCatalogSource source) {
    final changed = !_sameCatalog(_current, items) || _source != source;
    _current = List.unmodifiable(items);
    _source = source;
    if (changed) notifyListeners();
  }

  static List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> response) {
    final raw = response['rideTypes'] ?? response['data'];
    if (raw is! List) {
      throw const FormatException('ride-types payload has no list');
    }
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static bool _sameCatalog(List<RideCatalogItem> a, List<RideCatalogItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.name != y.name ||
          x.note != y.note ||
          x.etaMin != y.etaMin ||
          x.price != y.price ||
          x.currency != y.currency ||
          x.seats != y.seats ||
          x.badge != y.badge ||
          x.glyph != y.glyph ||
          x.image != y.image) {
        return false;
      }
    }
    return true;
  }
}

/// Maps the server's ride-type rows onto [RideCatalogItem].
///
/// Disabled rows are dropped and the rest sorted by `order`. An `imageKey`
/// the app has no asset for shows the generic Movera car; a `glyph` it has
/// no icon for shows a plain car glyph.
class RideCatalogJson {
  const RideCatalogJson._();

  static const imageDir = 'assets/images/rides';
  static const fallbackImage = '$imageDir/movera.webp';
  static const knownImages = <String>{
    'movera',
    'comfort',
    'premium',
    'priority',
    'xl',
    'electric',
    'pet',
    'van',
    'wheelchair',
    'business',
    'airport',
    'kids',
    'women',
    'delivery',
  };
  static const knownGlyphs = <String>{
    'bolt',
    'pets',
    'van',
    'wheelchair',
    'briefcase',
    'plane',
    'child',
    'person',
    'parcel',
  };

  /// The glyph key a screen draws as a generic car.
  static const fallbackGlyph = 'car';

  static List<RideCatalogItem> parseAll(Iterable<Map<String, dynamic>> rows) {
    final indexed = <(int, int, RideCatalogItem)>[];
    var position = 0;
    for (final row in rows) {
      final item = parse(row);
      position += 1;
      if (item == null) continue;
      final order = (row['order'] as num?)?.toInt() ?? position;
      indexed.add((order, position, item));
    }
    indexed.sort((a, b) {
      final byOrder = a.$1.compareTo(b.$1);
      return byOrder != 0 ? byOrder : a.$2.compareTo(b.$2);
    });
    return indexed.map((entry) => entry.$3).toList();
  }

  /// One row, or null when it is disabled or unusable.
  static RideCatalogItem? parse(Map<String, dynamic> row) {
    // Contract v0.3.0: canonical category ids; `movera` reads as `economy`.
    final rawId = _string(row['id']);
    final id = rawId == null ? null : CategoryIds.canonical(rawId);
    final name = _string(row['name']);
    if (id == null || name == null) return null;
    final enabled = row['enabled'];
    if (enabled is bool && !enabled) return null;
    // Contract v0.3.0: `price: Money`; a bare number is the pre-v0.3 kronor.
    final rawPrice = row['price'];
    final listPrice =
        Money.fromWire(rawPrice) ??
        (rawPrice is num ? Money.fromLegacyMajor(rawPrice) : null);
    final price = listPrice?.major;
    if (price == null || price < 0) return null;
    final etaMin = ((row['etaMin'] as num?)?.toInt() ?? 0).clamp(0, 999);
    final seats = ((row['seats'] as num?)?.toInt() ?? 4).clamp(1, 99);
    return RideCatalogItem(
      id: id,
      image: imageFor(_string(row['imageKey']) ?? id),
      name: name,
      note: _string(row['description']) ?? '',
      arrival: '$etaMin min',
      etaMin: etaMin,
      price: price,
      currency: listPrice!.currency,
      seats: seats,
      badge: _string(row['badge']),
      glyph: glyphFor(_string(row['glyph'])),
    );
  }

  /// Category ids whose picture ships under another name.
  static const _assetAliases = <String, String>{
    'economy': 'movera',
    'child_seat': 'kids',
  };

  static String imageFor(String key) {
    final raw = key.trim().toLowerCase();
    final clean = _assetAliases[raw] ?? raw;
    if (knownImages.contains(clean)) return '$imageDir/$clean.webp';
    return fallbackImage;
  }

  static String? glyphFor(String? key) {
    if (key == null) return null;
    final clean = key.trim().toLowerCase();
    if (clean.isEmpty || clean == 'none') return null;
    if (knownGlyphs.contains(clean)) return clean;
    return fallbackGlyph;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
