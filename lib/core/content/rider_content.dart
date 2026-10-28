/// Content published from the admin's Content page (contract v0.10.0 §19,
/// `contract.json#content`): the six rider banners, Help, Legal and the
/// app versions. Each item carries a title and a text in sv, fr and en.
class ContentItem {
  const ContentItem({
    required this.slot,
    required this.version,
    required this.title,
    required this.text,
    this.zoneId,
    this.publishedAt,
    this.image,
    this.expiresAt,
    this.reaccept = false,
    this.riderMin,
    this.riderRecommended,
  });

  static const bannerSlots = [
    'rider-banner-1',
    'rider-banner-2',
    'rider-banner-3',
    'rider-banner-4',
    'rider-banner-5',
    'rider-banner-6',
  ];

  final String slot;
  final String? zoneId;
  final int version;
  final DateTime? publishedAt;
  final String title;

  /// `{ sv, fr, en }`.
  final Map<String, String> text;

  /// Only an https URL is kept.
  final String? image;
  final DateTime? expiresAt;

  /// Legal only: the rider must accept this version again.
  final bool reaccept;

  /// App versions only: the rider app's pair.
  final String? riderMin;
  final String? riderRecommended;

  /// The text in [language], else English, else any.
  String textIn(String language) {
    final own = text[language];
    if (own != null && own.trim().isNotEmpty) return own;
    final en = text['en'];
    if (en != null && en.trim().isNotEmpty) return en;
    return text.values.firstWhere((t) => t.trim().isNotEmpty, orElse: () => '');
  }

  bool liveAt(DateTime now) => expiresAt == null || now.isBefore(expiresAt!);

  static ContentItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final slot = json['slot'];
    final version = json['version'];
    final title = json['title'];
    final rawText = json['text'];
    if (slot is! String || version is! num || title is! String) return null;
    final text = <String, String>{
      if (rawText is Map)
        for (final e in rawText.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    final image = json['image'];
    final expires = json['expiresAt'];
    final published = json['publishedAt'];
    final versions = json['versions'];
    final rider = versions is Map ? versions['rider'] : null;
    String? semver(Object? v) =>
        v is String && parseVersion(v) != null ? v.trim() : null;
    return ContentItem(
      slot: slot,
      zoneId: json['zoneId'] is String ? json['zoneId'] as String : null,
      version: version.toInt(),
      publishedAt: published is String ? DateTime.tryParse(published) : null,
      title: title,
      text: text,
      image: image is String && image.startsWith('https://') ? image : null,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      reaccept: json['reaccept'] == true,
      riderMin: rider is Map ? semver(rider['min']) : null,
      riderRecommended: rider is Map ? semver(rider['recommended']) : null,
    );
  }
}

/// `x.y.z` as three numbers (a `+build` or `-pre` suffix is dropped), or
/// null when [value] is no such version (a local `dev` build).
List<int>? parseVersion(String value) {
  final core = value.trim().split(RegExp(r'[+-]')).first;
  final parts = core.split('.');
  if (parts.length != 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null || n < 0)) return null;
  return numbers.cast<int>();
}

/// Whether [running] is below [floor]. False when either is not `x.y.z`,
/// so a build that does not know its version is never blocked.
bool versionBelow(String running, String? floor) {
  if (floor == null) return false;
  final a = parseVersion(running);
  final b = parseVersion(floor);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

/// The answer of `GET /rider/content?zoneId`.
class RiderContent {
  const RiderContent(this.items);

  static const empty = RiderContent([]);

  final List<ContentItem> items;

  static RiderContent? fromJson(Object? json) {
    if (json is! Map || json['items'] is! List) return null;
    return RiderContent([
      for (final raw in json['items'] as List)
        if (ContentItem.fromJson(raw) case final item?) item,
    ]);
  }

  /// The newest live item of [slot].
  ContentItem? latest(String slot, DateTime now) {
    ContentItem? best;
    for (final item in items) {
      if (item.slot != slot || !item.liveAt(now)) continue;
      if (best == null || item.version > best.version) best = item;
    }
    return best;
  }

  /// The live rider banners, in slot order 1…6.
  List<ContentItem> banners(DateTime now) => [
    for (final slot in ContentItem.bannerSlots)
      if (latest(slot, now) case final item?) item,
  ];

  ContentItem? help(DateTime now) => latest('help', now);
  ContentItem? legal(DateTime now) => latest('legal', now);
  ContentItem? appVersions(DateTime now) => latest('app-versions', now);
}

enum UpdateNeed { none, recommended, required }

/// What the content asks of the app right now (§19 rules).
class ContentDecision {
  const ContentDecision({
    this.blockForUpdate = false,
    this.acceptTerms,
    this.recommendUpdate = false,
    this.tripUpdateNotice = false,
  });

  /// Full screen "Update the app"; nothing but SOS works.
  final bool blockForUpdate;

  /// The legal item to accept before anything else (full screen).
  final ContentItem? acceptTerms;

  /// A message the rider can close.
  final bool recommendUpdate;

  /// On a trip below the minimum: only a small message; the block follows
  /// the trip.
  final bool tripUpdateNotice;

  static UpdateNeed updateNeed(ContentItem? versions, String running) {
    if (versions == null) return UpdateNeed.none;
    if (versionBelow(running, versions.riderMin)) return UpdateNeed.required;
    if (versionBelow(running, versions.riderRecommended)) {
      return UpdateNeed.recommended;
    }
    return UpdateNeed.none;
  }

  /// [legalAtStart] is the legal item known when the app started (the terms
  /// show at an app start, never mid-session); [acceptedLegalVersion] the
  /// version this rider accepted.
  static ContentDecision decide({
    required RiderContent content,
    required DateTime now,
    required String appVersion,
    required bool onTrip,
    required ContentItem? legalAtStart,
    required int? acceptedLegalVersion,
    required bool recommendedClosed,
  }) {
    final need = updateNeed(content.appVersions(now), appVersion);
    if (need == UpdateNeed.required) {
      return onTrip
          ? const ContentDecision(tripUpdateNotice: true)
          : const ContentDecision(blockForUpdate: true);
    }
    final legal = legalAtStart;
    final mustAccept =
        legal != null &&
        legal.reaccept &&
        legal.liveAt(now) &&
        (acceptedLegalVersion == null || acceptedLegalVersion < legal.version);
    return ContentDecision(
      acceptTerms: mustAccept && !onTrip ? legal : null,
      recommendUpdate: need == UpdateNeed.recommended && !recommendedClosed,
    );
  }
}
