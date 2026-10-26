import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/web_reverse_geocode.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// A street-name lookup outside the Movera backend (the web demo's
/// OpenStreetMap fallback).
typedef PublicReverseGeocoder = Future<String?> Function(
  GeoPoint point, {
  Duration timeout,
});

class AppGeocoding implements GeocodingRepository {
  AppGeocoding({
    ApiClient? api,
    this.cacheTtl = const Duration(minutes: 10),
    Duration? requestTimeout,
    int? retries,
    this.retryDelay = defaultRetryDelay,
    this.allowPublicReverseFallback = false,
    PublicReverseGeocoder? publicReverse,
    bool? isWeb,
  }) : _api = api,
       requestTimeout =
           requestTimeout ??
           (api?.contractWire == true
               ? liveRequestTimeout
               : mockRequestTimeout),
       retries = retries ?? (api?.contractWire == true ? 1 : 0),
       _publicReverse = publicReverse ?? openStreetMapReverse,
       _isWeb = isWeb ?? kIsWeb;

  /// How long one address lookup may take against movera-server (the
  /// contract wire: staging, production). The live server is slow (a
  /// small instance that wakes from sleep in 30-50 s); the old 8 s turned
  /// a slow answer into "Couldn't reach Movera" on the address screen and
  /// the pin, while the screens show a progress indicator meanwhile.
  static const liveRequestTimeout = Duration(seconds: 25);

  /// The limit with the in-process mock (demo, dev, test), which answers
  /// at once; the tests of the pin and Set pickup wait this out.
  static const mockRequestTimeout = Duration(seconds: 8);

  /// On the contract wire, a lookup refused by a transient server fault
  /// (503 while it wakes, 429, a dropped connection) is asked once more
  /// after this pause. A timeout is not retried: the rider has waited
  /// long enough. The mock has no such faults and gets no retry.
  static const defaultRetryDelay = Duration(seconds: 2);

  final ApiClient? _api;

  /// Whether the browser may ask public OpenStreetMap Nominatim for a street
  /// name when the backend has none. Only demo/dev/test builds turn this on
  /// (`AppEnv.allowsMockTransport`): it sends the rider's exact coordinates
  /// to a third party, so staging and production rely on the backend's
  /// reverse geocoder alone.
  final bool allowPublicReverseFallback;
  final PublicReverseGeocoder _publicReverse;
  final bool _isWeb;
  final Duration cacheTtl;
  final Duration requestTimeout;

  /// How many more times a lookup is tried after a transient fault.
  final int retries;
  final Duration retryDelay;
  final Map<String, _CachedValue<PlaceResult?>> _forwardCache = {};
  final Map<String, _CachedValue<String?>> _reverseCache = {};
  final Map<String, Future<PlaceResult?>> _forwardInFlight = {};
  final Map<String, Future<String?>> _reverseInFlight = {};

  @override
  Future<PlaceResult?> forward(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;
    final key = normalized.toLowerCase();
    final cached = _forwardCache[key];
    if (cached != null && cached.isFresh(cacheTtl)) return cached.value;

    final existing = _forwardInFlight[key];
    if (existing != null) return existing;

    final future = _forwardFromApi(normalized);
    _forwardInFlight[key] = future;
    try {
      final result = await future;
      _forwardCache[key] = _CachedValue(result);
      return result;
    } finally {
      if (identical(_forwardInFlight[key], future))
        _forwardInFlight.remove(key);
    }
  }

  @override
  Future<String?> reverse(GeoPoint point) async {
    // rider-r4-44: street names come back in the app language, so an
    // address looked up before a language switch is not reused after it.
    final key =
        '${L10n.code}:${point.latitude.toStringAsFixed(5)}:'
        '${point.longitude.toStringAsFixed(5)}';
    final cached = _reverseCache[key];
    if (cached != null && cached.isFresh(cacheTtl)) return cached.value;

    final existing = _reverseInFlight[key];
    if (existing != null) return existing;

    final future = _reverseFromApi(point);
    _reverseInFlight[key] = future;
    try {
      final result = await future;
      // rider-r4-43: the placeholder is what a failed street lookup leaves
      // (Nominatim rate-limits easily); caching it would show 'Current
      // location' at this spot for the whole TTL. The next lookup retries.
      if (result != null && result != placeholderReverseLabel) {
        _reverseCache[key] = _CachedValue(result);
      }
      return result;
    } finally {
      if (identical(_reverseInFlight[key], future))
        _reverseInFlight.remove(key);
    }
  }

  Future<String?> reverseGeocodeAddress(double latitude, double longitude) {
    return reverse(GeoPoint(latitude, longitude));
  }

  Future<PlaceResult?> geocodeAddress(String address) => forward(address);

  Future<PlaceResult?> _forwardFromApi(String query) async {
    final api = _requireApi();
    final response = await _onceMore(
      () => api
          .post('/api/v1/locations/geocode', body: {'query': query})
          .timeout(requestTimeout),
    );
    final data = _payload(response);
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (latitude is! num || longitude is! num) return null;
    return PlaceResult(
      address: data['address'] as String? ?? query,
      point: GeoPoint(latitude.toDouble(), longitude.toDouble()),
    );
  }

  Future<String?> _reverseFromApi(GeoPoint point) async {
    final api = _requireApi();
    final response = await _onceMore(
      () => api
          .post(
            '/api/v1/locations/reverse-geocode',
            body: {'latitude': point.latitude, 'longitude': point.longitude},
          )
          .timeout(requestTimeout),
    );
    final data = _payload(response);
    final address = data['address'];
    final named = address is String && address.trim().isNotEmpty
        ? address.trim()
        : null;
    // The web demo's in-process transport knows no street names and answers
    // with a neutral label; the rider still wants to read where they are.
    if (allowPublicReverseFallback &&
        _isWeb &&
        (named == null || named == placeholderReverseLabel)) {
      final street = await _publicReverse(point, timeout: requestTimeout);
      if (street != null) return street;
    }
    return named;
  }

  /// What a transport without a geocoder answers instead of an address.
  static const String placeholderReverseLabel = 'Current location';

  /// Runs [request]; a transient server fault (5xx, 429, no connection)
  /// gets [retries] more tries, each after [retryDelay]. A timeout or a
  /// definite answer (4xx, a bad payload) is not tried again.
  Future<Map<String, dynamic>> _onceMore(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    var left = retries;
    while (true) {
      try {
        return await request();
      } catch (error) {
        if (left <= 0 || !isTransientFault(error)) rethrow;
        left -= 1;
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  /// Whether [error] says nothing final about the lookup: the server
  /// failed or refused the load (5xx, 429) or the request never arrived.
  static bool isTransientFault(Object error) {
    if (error is ApiError) {
      final status = error.statusCode ?? 0;
      return status >= 500 || status == 429 || error.code == 'NETWORK';
    }
    return error is http.ClientException;
  }

  ApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw StateError(
        'AppGeocoding requires the authenticated Movera ApiClient',
      );
    }
    return api;
  }

  static Map<String, dynamic> _payload(Map<String, dynamic> response) {
    final data = response['data'];
    return data is Map ? Map<String, dynamic>.from(data) : response;
  }
}

class _CachedValue<T> {
  _CachedValue(this.value) : storedAt = DateTime.now();

  final T value;
  final DateTime storedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(storedAt) <= ttl;
}
