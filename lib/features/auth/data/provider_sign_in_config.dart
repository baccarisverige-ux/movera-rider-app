import 'package:flutter/foundation.dart';

/// The Apple and Google client ids this build may use, from build-time
/// `--dart-define`s (the build workflows pass them from repository
/// variables). An empty value keeps that provider on "coming soon" on the
/// platform that needs it; nothing here is a secret.
///
/// * `GOOGLE_CLIENT_ID_WEB`: Google OAuth client of type "Web application"
///   (the web build; its JavaScript origin is the GitHub Pages site).
/// * `GOOGLE_CLIENT_ID_IOS`: Google OAuth client of type "iOS" (bundle id).
/// * `GOOGLE_SERVER_CLIENT_ID`: the Web client id again, as the audience of
///   the Android and iOS tokens (Android needs it; its own Android client
///   only has to exist in the same Google Cloud project).
/// * `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`: Apple Services ID and its
///   return URL, for Apple on the web and on Android. iOS uses the native
///   sheet and needs neither.
@immutable
class ProviderSignInConfig {
  const ProviderSignInConfig({
    String googleWebClientId = '',
    String googleIosClientId = '',
    String googleServerClientId = '',
    String appleServiceId = '',
    String appleRedirectUri = '',
  }) : _googleWebClientId = googleWebClientId,
       _googleIosClientId = googleIosClientId,
       _googleServerClientId = googleServerClientId,
       _appleServiceId = appleServiceId,
       _appleRedirectUri = appleRedirectUri;

  /// The values compiled into this build.
  static const ProviderSignInConfig fromEnvironment = ProviderSignInConfig(
    googleWebClientId: _envGoogleWeb,
    googleIosClientId: _envGoogleIos,
    googleServerClientId: _envGoogleServer,
    appleServiceId: _envAppleServiceId,
    appleRedirectUri: _envAppleRedirectUri,
  );

  // One const read per line (test/audit/web_const_environment_test.dart).
  static const _envGoogleWeb = String.fromEnvironment('GOOGLE_CLIENT_ID_WEB');
  static const _envGoogleIos = String.fromEnvironment('GOOGLE_CLIENT_ID_IOS');
  static const _envGoogleServer = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _envAppleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
  static const _envAppleRedirectUri = String.fromEnvironment(
    'APPLE_REDIRECT_URI',
  );

  final String _googleWebClientId;
  final String _googleIosClientId;
  final String _googleServerClientId;
  final String _appleServiceId;
  final String _appleRedirectUri;

  // A pasted space or line break never reaches the SDK.
  static String _clean(String value) =>
      value.replaceAll(RegExp(r'[\s\u0000-\u001f]'), '');

  String get googleWebClientId => _clean(_googleWebClientId);
  String get googleIosClientId => _clean(_googleIosClientId);
  String get googleServerClientId => _clean(_googleServerClientId);
  String get appleServiceId => _clean(_appleServiceId);

  /// Null unless it is an absolute https address.
  Uri? get appleRedirectUri {
    final uri = Uri.tryParse(_clean(_appleRedirectUri));
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  /// The Google client id to pass to `initialize(clientId:)` on [platform]
  /// (web or iOS), or null when Google stays "coming soon" there.
  /// Android has no client id of its own: [googleServerClientIdFor].
  String? googleClientIdFor({
    required bool web,
    required TargetPlatform platform,
  }) {
    if (web) return _orNull(googleWebClientId);
    if (platform == TargetPlatform.iOS) return _orNull(googleIosClientId);
    return null;
  }

  /// `initialize(serverClientId:)`: required on Android, optional on iOS
  /// (the token's audience is then the Web client), never on the web.
  String? googleServerClientIdFor({
    required bool web,
    required TargetPlatform platform,
  }) {
    if (web) return null;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return _orNull(googleServerClientId);
    }
    return null;
  }

  /// Whether Google can be asked on this build and platform.
  bool googleAvailable({required bool web, required TargetPlatform platform}) {
    if (web) return googleWebClientId.isNotEmpty;
    return switch (platform) {
      TargetPlatform.android => googleServerClientId.isNotEmpty,
      TargetPlatform.iOS => googleIosClientId.isNotEmpty,
      _ => false,
    };
  }

  /// Apple: the native sheet on iOS and macOS; the web flow (Services ID
  /// and return URL) on the web and Android.
  bool appleAvailable({required bool web, required TargetPlatform platform}) {
    if (!web &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
      return true;
    }
    if (web || platform == TargetPlatform.android) {
      return appleServiceId.isNotEmpty && appleRedirectUri != null;
    }
    return false;
  }

  static String? _orNull(String value) => value.isEmpty ? null : value;
}
