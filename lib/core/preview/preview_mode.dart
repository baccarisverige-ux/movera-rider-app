import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:movera_rider/l10n/generated/app_localizations.dart';

import 'package:movera_rider/core/auth/token_store.dart';

/// Contract v0.18.25 `previewSession` (BASE job B7, owner P1 a / P2 b):
/// the admin panel frames this web app at
/// `<url>#movera-preview=<token>&zone=<zoneId>&draft=<0|1>`. The app then
/// reads the live server with that read-only token, shows a "Preview"
/// banner, and never sends a write: every POST / PUT / PATCH / DELETE stops
/// in the API client with "Preview – not sent" (the server would refuse it
/// anyway, 403 `preview_blocked`).
class PreviewMode {
  const PreviewMode({this.token, this.zoneId, this.draft = false});

  /// Not a preview (a normal app start).
  static const off = PreviewMode();

  /// The fragment key the admin panel uses.
  static const fragmentKey = 'movera-preview';

  /// The server's reason for a refused preview write.
  static const blockedReason = 'preview_blocked';

  /// The preview token, or null outside a preview.
  final String? token;
  final String? zoneId;

  /// true: config reads ask for the zone's saved draft (`?draft=1`).
  final bool draft;

  bool get active => token != null && token!.isNotEmpty;

  /// Reads the preview hand-off from a web URL's fragment.
  static PreviewMode parse(Uri uri) {
    final fragment = uri.fragment;
    if (!fragment.contains('$fragmentKey=')) return off;
    final Map<String, String> values;
    try {
      values = Uri.splitQueryString(
        fragment.startsWith('/') ? fragment.substring(1) : fragment,
      );
    } on FormatException {
      return off;
    }
    final token = values[fragmentKey];
    if (token == null || !RegExp(r'^[A-Za-z0-9_\-.]+$').hasMatch(token)) {
      return off;
    }
    return PreviewMode(
      token: token,
      zoneId: values['zone'],
      draft: values['draft'] == '1',
    );
  }

  /// This run's preview: web builds only (a phone app is never a preview).
  static PreviewMode current = off;

  /// Reads the hand-off once, first thing in `main`, before the app's
  /// router can change the URL.
  static void readFromUrl() {
    if (kIsWeb) current = parse(Uri.base);
  }

  /// Counts the writes the preview stopped; the banner shows "Preview –
  /// not sent" for a moment after each one.
  static final ValueNotifier<int> blocked = ValueNotifier<int>(0);

  /// [path] with `draft=1` added when this preview shows the draft and the
  /// path reads an app config document.
  String withDraft(String path) {
    if (!active || !draft) return path;
    final plain = path.split('?').first;
    if (!plain.endsWith('/config')) return path;
    return path.contains('?') ? '$path&draft=1' : '$path?draft=1';
  }

  /// "Preview" in the app's language (contract `previewSession.appTexts`).
  static String bannerText(String language) =>
      lookupAppLocalizations(_locale(language)).previewBanner;

  /// "Preview – not sent" in the app's language.
  static String notSentText(String language) =>
      lookupAppLocalizations(_locale(language)).previewNotSent;

  static Locale _locale(String language) =>
      Locale(const {'sv', 'fr'}.contains(language) ? language : 'en');

  /// The device language, for texts made outside a widget.
  static String get deviceLanguage =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
}

/// The preview's token as the session: an access token only, never saved,
/// never refreshed (a refresh is a write).
class PreviewTokenStore implements TokenStore {
  PreviewTokenStore(this._access);

  final String _access;

  @override
  Future<void> save({required String access, required String refresh}) async {}

  @override
  Future<String?> readAccess() async => _access;

  @override
  Future<String?> readRefresh() async => null;

  @override
  Future<void> clear() async {}
}

/// The "Preview" strip at the top of the app; it reads "Preview – not sent"
/// for three seconds after a stopped write.
class PreviewBanner extends StatefulWidget {
  const PreviewBanner({super.key});

  @override
  State<PreviewBanner> createState() => _PreviewBannerState();
}

class _PreviewBannerState extends State<PreviewBanner> {
  bool _notSent = false;
  int _seen = PreviewMode.blocked.value;

  @override
  void initState() {
    super.initState();
    PreviewMode.blocked.addListener(_onBlocked);
  }

  @override
  void dispose() {
    PreviewMode.blocked.removeListener(_onBlocked);
    super.dispose();
  }

  void _onBlocked() {
    if (PreviewMode.blocked.value == _seen) return;
    _seen = PreviewMode.blocked.value;
    setState(() => _notSent = true);
    final mark = _seen;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && mark == _seen) setState(() => _notSent = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final language =
        Localizations.maybeLocaleOf(context)?.languageCode ??
        PreviewMode.deviceLanguage;
    final text = _notSent
        ? PreviewMode.notSentText(language)
        : PreviewMode.bannerText(language);
    return SafeArea(
      bottom: false,
      child: Semantics(
        liveRegion: true,
        label: text,
        child: ColoredBox(
          color: _notSent ? const Color(0xFFB54708) : const Color(0xFF175CD3),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Center(
              child: Text(
                text,
                key: const Key('preview-banner'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
