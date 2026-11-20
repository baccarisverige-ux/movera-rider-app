import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';

/// v0.18.147 (contract.json#driverProfile; owner 2026-11-20 "Now build
/// all"): the six compliment chips in the contract's order, each drawn with
/// the phone's own emoji as text (no image file).
const complimentEmoji = <String, String>{
  'great_service': '⭐',
  'knew_the_way': '\u{1F9ED}',
  'friendly': '\u{1F4AC}',
  'clean_car': '✨',
  'safe_driving': '\u{1F6E1}',
  'good_music': '\u{1F3B5}',
};

/// contract.json#driverProfile.languages.codes, each in its own language.
const profileLanguageNames = <String, String>{
  'sv': 'Svenska',
  'en': 'English',
  'ar': 'العربية',
  'fr': 'Français',
  'fi': 'Suomi',
  'es': 'Español',
  'de': 'Deutsch',
  'fa': 'فارسی',
  'so': 'Soomaali',
  'ti': 'ትግርኛ',
  'tr': 'Türkçe',
  'pl': 'Polski',
  'ru': 'Русский',
  'ku': 'Kurdî',
  'bs': 'Bosanski',
  'uk': 'Українська',
};

/// The zone's switches, `RiderAppConfig.driverProfile { on, reviews }`
/// (defaults: on, reviews off). Set from the served rider document.
class DriverProfileSettings {
  const DriverProfileSettings({required this.on, required this.reviews});
  static const defaults = DriverProfileSettings(on: true, reviews: false);
  static DriverProfileSettings current = defaults;
  final bool on;
  final bool reviews;

  static DriverProfileSettings fromJson(Object? json) {
    if (json is! Map) return defaults;
    return DriverProfileSettings(
      on: json['on'] is bool ? json['on'] as bool : defaults.on,
      reviews: json['reviews'] is bool
          ? json['reviews'] as bool
          : defaults.reviews,
    );
  }
}

class DriverCompliment {
  const DriverCompliment(this.code, this.count);
  final String code;
  final int count;
}

/// `DriverPublicProfile` (no rider data: the review carries only the
/// first name the rider allowed, or none, and the month).
class DriverPublicProfile {
  const DriverPublicProfile({
    required this.firstName,
    this.verified = false,
    this.photoUrl,
    this.languages = const [],
    this.city,
    this.sinceMonth,
    this.years,
    this.tripCount = 0,
    this.rating,
    this.compliments = const [],
    this.milestones = const [],
    this.reviewText,
    this.reviewName,
    this.reviewMonth,
  });

  final String firstName;
  final bool verified;
  final String? photoUrl;
  final List<String> languages;
  final String? city;
  final String? sinceMonth;
  final int? years;
  final int tripCount;
  final double? rating;
  final List<DriverCompliment> compliments;
  final List<String> milestones;
  final String? reviewText;
  final String? reviewName;
  final String? reviewMonth;

  factory DriverPublicProfile.fromJson(Map<String, dynamic> j) {
    final r = j['latestReview'];
    return DriverPublicProfile(
      firstName: (j['firstName'] as String?) ?? '',
      verified: j['verified'] == true,
      photoUrl: j['photoUrl'] as String?,
      languages: [
        for (final l in (j['languages'] as List? ?? const []))
          if (l is String) l,
      ],
      city: j['city'] as String?,
      sinceMonth: j['sinceMonth'] as String?,
      years: (j['years'] as num?)?.toInt(),
      tripCount: (j['tripCount'] as num?)?.toInt() ?? 0,
      rating: (j['rating'] as num?)?.toDouble(),
      compliments: [
        for (final c in (j['compliments'] as List? ?? const []))
          if (c is Map &&
              complimentEmoji.containsKey(c['code']) &&
              c['count'] is num)
            DriverCompliment(c['code'] as String, (c['count'] as num).toInt()),
      ],
      milestones: [
        for (final m in (j['milestones'] as List? ?? const []))
          if (m is Map && m['code'] is String) m['code'] as String,
      ],
      reviewText: r is Map ? r['text'] as String? : null,
      reviewName: r is Map ? r['name'] as String? : null,
      reviewMonth: r is Map ? r['month'] as String? : null,
    );
  }
}

/// LOAD RULE (owner): read once when the sheet opens, kept 5 minutes per
/// trip in memory; no polling. Null = the zone's profile is off or the
/// read failed (the caller shows the simple page).
abstract final class DriverProfiles {
  static const keepFor = Duration(minutes: 5);
  static final Map<String, ({DateTime at, DriverPublicProfile profile})> _kept =
      {};
  static final Map<String, Future<DriverPublicProfile?>> _loading = {};

  @visibleForTesting
  static ApiClient? debugApi;
  @visibleForTesting
  static DateTime Function() now = DateTime.now;
  @visibleForTesting
  static int reads = 0;

  static String pathOf(String tripId) =>
      '/api/v1/rider/trips/${Uri.encodeComponent(tripId)}/driver-profile';

  static Future<DriverPublicProfile?> load(String tripId) {
    final kept = _kept[tripId];
    if (kept != null && now().difference(kept.at) < keepFor) {
      return Future.value(kept.profile);
    }
    return _loading[tripId] ??= _fetch(tripId).whenComplete(() {
      _loading.remove(tripId);
    });
  }

  static Future<DriverPublicProfile?> _fetch(String tripId) async {
    try {
      reads++;
      final api = debugApi ?? AppScope.instance.api;
      final p = DriverPublicProfile.fromJson(await api.get(pathOf(tripId)));
      _kept[tripId] = (at: now(), profile: p);
      return p;
    } catch (_) {
      return null;
    }
  }

  static void clear() {
    _kept.clear();
    _loading.clear();
  }
}
