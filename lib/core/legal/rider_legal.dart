import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// One legal text (contract v0.18.5 `LegalDocument`): title and text in
/// sv / fr / en, the company placeholders already filled by the server.
class LegalDocument {
  const LegalDocument({required this.title, required this.text});

  final Map<String, String> title;
  final Map<String, String> text;

  static LegalDocument? fromJson(Object? raw) {
    if (raw is! Map) return null;
    Map<String, String>? langs(Object? value) {
      if (value is! Map) return null;
      final out = <String, String>{
        for (final e in value.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
      return out.isEmpty ? null : out;
    }

    final title = langs(raw['title']);
    final text = langs(raw['text']);
    if (title == null || text == null) return null;
    return LegalDocument(title: title, text: text);
  }

  Map<String, Object?> toJson() => {'title': title, 'text': text};

  static String _in(Map<String, String> m, String code) =>
      m[code] ?? m['en'] ?? m.values.first;

  String titleIn(String code) => _in(title, code);

  /// The text's paragraphs: the server separates them by a blank line.
  List<String> paragraphsIn(String code) => _in(
    text,
    code,
  ).split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

/// `GET /legal/{country}` → `LegalTexts` (contract v0.18.5 `legal.read`).
class LegalTexts {
  const LegalTexts({
    required this.country,
    required this.version,
    required this.reaccept,
    required this.terms,
    required this.privacy,
    this.source = 'default',
  });

  final String country;

  /// 0 = Movera's draft texts (nothing published by the admin yet).
  final int version;
  final String source;
  final bool reaccept;
  final LegalDocument terms;
  final LegalDocument privacy;

  LegalDocument of(String kind) => kind == 'privacy' ? privacy : terms;

  static LegalTexts? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final country = raw['country'];
    final version = raw['version'];
    final terms = LegalDocument.fromJson(raw['terms']);
    final privacy = LegalDocument.fromJson(raw['privacy']);
    if (country is! String ||
        version is! num ||
        terms == null ||
        privacy == null) {
      return null;
    }
    return LegalTexts(
      country: country,
      version: version.toInt(),
      source: raw['source'] is String ? raw['source'] as String : 'default',
      reaccept: raw['reaccept'] == true,
      terms: terms,
      privacy: privacy,
    );
  }

  Map<String, Object?> toJson() => {
    'country': country,
    'version': version,
    'source': source,
    'reaccept': reaccept,
    'terms': terms.toJson(),
    'privacy': privacy.toJson(),
  };
}

/// The last answer per country (read offline) and the version the rider
/// accepted, on this device.
abstract class LegalStore {
  Future<LegalTexts?> read(String country);
  Future<void> write(LegalTexts texts);
  Future<int?> accepted(String country);
  Future<void> writeAccepted(String country, int version);
}

class PrefsLegalStore implements LegalStore {
  const PrefsLegalStore();

  static String textsKey(String country) => 'movera_rider_legal_v1_$country';
  static String acceptedKey(String country) =>
      'movera_rider_legal_accepted_v1_$country';

  @override
  Future<LegalTexts?> read(String country) async {
    final raw = (await PreferencesStore.load()).getString(textsKey(country));
    if (raw == null) return null;
    return LegalTexts.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> write(LegalTexts texts) async => (await PreferencesStore.load())
      .setString(textsKey(texts.country), jsonEncode(texts.toJson()));

  @override
  Future<int?> accepted(String country) async =>
      (await PreferencesStore.load()).getInt(acceptedKey(country));

  @override
  Future<void> writeAccepted(String country, int version) async =>
      (await PreferencesStore.load()).setInt(acceptedKey(country), version);
}

class MemoryLegalStore implements LegalStore {
  final Map<String, LegalTexts> texts = {};
  final Map<String, int> acceptedVersions = {};

  @override
  Future<LegalTexts?> read(String country) async => texts[country];

  @override
  Future<void> write(LegalTexts value) async => texts[value.country] = value;

  @override
  Future<int?> accepted(String country) async => acceptedVersions[country];

  @override
  Future<void> writeAccepted(String country, int version) async =>
      acceptedVersions[country] = version;
}

/// Terms of use and privacy policy (contract v0.18.5 §30 `legal`, owner
/// G1-B2 "Real texts from admin (Recommended)").
///
/// - Read from `GET /legal/{country}` (no token, so also on the sign-in
///   screen) on start and whenever the app comes back to the foreground;
///   the last answer is kept for offline use.
/// - Country: the start country before sign-in, the rider's zone country
///   after ([country]).
/// - Re-accept: when the answer known at this app start has `reaccept` and
///   the rider has not accepted that version, [mustAccept] is true (never
///   during a trip, never signed out) until `POST /account/legal/accept`.
///   A later publish shows at the next start, never mid-session; a booking
///   refused with `terms_not_accepted` arms it at once ([onTermsNotAccepted]).
/// Never throws to its callers.
class RiderLegalController extends ChangeNotifier {
  RiderLegalController({
    this.api,
    LegalStore? store,
    ValueListenable<bool>? onTrip,
    required this.country,
  }) : _store = store ?? const PrefsLegalStore(),
       onTrip = onTrip ?? ValueNotifier(false) {
    this.onTrip.addListener(_changed);
  }

  static String pathOf(String country) =>
      '/api/v1/legal/${Uri.encodeComponent(country)}';
  static const acceptPath = '/api/v1/account/legal/accept';

  final ApiClient? api;
  final LegalStore _store;
  final ValueListenable<bool> onTrip;

  /// `SE` or `FR` (contract `legal.countries`).
  final Future<String> Function() country;

  LegalTexts? _texts;
  LegalTexts? get texts => _texts;

  /// The answer known when this app start's first read finished: the one
  /// re-accept is asked for.
  LegalTexts? _armed;
  final Map<String, int> _accepted = {};
  bool _signedIn = false;
  bool _loading = false;
  bool _failed = false;
  bool _startDone = false;
  bool _disposed = false;

  bool get loading => _loading;

  /// The last read failed and nothing is kept for this country.
  bool get failed => _failed && _texts == null;

  /// Full-screen "New terms" with "I accept".
  bool get mustAccept {
    final armed = _armed;
    if (!_signedIn || onTrip.value || armed == null) return false;
    if (!armed.reaccept || armed.version <= 0) return false;
    return (_accepted[armed.country] ?? 0) < armed.version;
  }

  LegalTexts? get toAccept => mustAccept ? _armed : null;

  /// After sign-in (and at a start with a session): re-accept may show.
  void signedIn() {
    _signedIn = true;
    _changed();
  }

  /// Sign-out: nothing to accept for nobody.
  void signedOut() {
    _signedIn = false;
    _changed();
  }

  /// Reads the kept answer, then the server's. [start] arms re-accept.
  Future<void> load({bool start = false}) async {
    final String code;
    try {
      code = await country();
    } catch (_) {
      return;
    }
    if (_texts?.country != code) {
      try {
        final kept = await _store.read(code);
        if (kept != null) _texts = kept;
        final accepted = await _store.accepted(code);
        if (accepted != null) _accepted[code] = accepted;
      } catch (error) {
        AppLog.warning('rider_legal.cache_failed', extra: {'error': '$error'});
      }
    }
    final client = api;
    if (client == null) return _changed();
    _loading = true;
    _changed();
    try {
      final parsed = LegalTexts.fromJson(await client.get(pathOf(code)));
      if (parsed == null) throw const FormatException('not LegalTexts');
      _texts = parsed;
      _failed = false;
      unawaited(
        _store.write(parsed).catchError((Object error) {
          AppLog.warning('rider_legal.ignored', extra: {'error': '$error'});
        }),
      );
    } catch (error) {
      _failed = true;
      AppLog.warning(
        'rider_legal.fetch_failed',
        extra: {'country': code, 'error': '$error'},
      );
    } finally {
      _loading = false;
      if (start || !_startDone) {
        _startDone = true;
        _armed = _texts;
      }
      _changed();
    }
  }

  /// The server refused a booking with `409 terms_not_accepted`.
  Future<void> onTermsNotAccepted() async {
    await load();
    _armed = _texts;
    _changed();
  }

  /// `POST /account/legal/accept { country, version }`. True when stored.
  Future<bool> accept() async {
    final armed = _armed;
    final client = api;
    if (armed == null || client == null) return true;
    try {
      await client.post(
        acceptPath,
        body: {'country': armed.country, 'version': armed.version},
        idempotencyKey: newIdempotencyKey('legal-accept'),
      );
    } catch (error) {
      if (error is ApiError && error.detail == 'terms_version_not_current') {
        // A newer version was published meanwhile: show that one.
        await load();
        _armed = _texts;
        _changed();
      }
      AppLog.warning('rider_legal.accept_failed', extra: {'error': '$error'});
      return false;
    }
    _accepted[armed.country] = armed.version;
    try {
      await _store.writeAccepted(armed.country, armed.version);
    } catch (error) {
      AppLog.warning('rider_legal.ignored', extra: {'error': '$error'});
    }
    _changed();
    return true;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onTrip.removeListener(_changed);
    super.dispose();
  }
}
