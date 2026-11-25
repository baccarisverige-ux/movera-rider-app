import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'google_web_script_stub.dart'
    if (dart.library.js_interop) 'google_web_script_web.dart';
import 'provider_sign_in_config.dart';

/// What the provider's SDK gave the app: the identity token the server
/// verifies (`POST /auth/provider { provider, idToken, app }`, contract §8)
/// and the name Apple shows only the first time (sent as `name`).
class ProviderIdentityToken {
  const ProviderIdentityToken({
    required this.provider,
    required this.idToken,
    this.name,
  });

  final String provider;
  final String idToken;
  final String? name;
}

/// Apple or Google cannot give a token on this build: the button then says
/// "coming soon – use your phone number", like the driver app and like a
/// server without provider keys (`503 provider_not_configured`).
class ProviderUnavailable implements Exception {
  const ProviderUnavailable(this.provider, [this.cause]);
  final String provider;
  final Object? cause;

  @override
  String toString() => 'ProviderUnavailable($provider, $cause)';
}

/// Gets the identity token from Apple or Google. Null when the rider
/// closed the provider's sheet without choosing an account.
abstract class ProviderTokenSource {
  Future<ProviderIdentityToken?> obtain(String provider);
}

/// Owner G1-E "Keep 'coming soon'" and G1-B1 "Fix it (Recommended)": the
/// first builds had no Apple or Google SDK, so every build answered
/// [ProviderUnavailable] and never sent a request without a token. Kept for
/// tests; the app now uses [PlatformProviderTokenSource] (owner 2026-11-23),
/// which gives the same answer on a build without client ids.
class NoProviderTokenSource implements ProviderTokenSource {
  const NoProviderTokenSource();

  @override
  Future<ProviderIdentityToken?> obtain(String provider) async =>
      throw ProviderUnavailable(provider);
}

/// The real SDKs: `sign_in_with_apple` (native sheet on iOS and macOS, the
/// Services ID web flow on the web and Android) and `google_sign_in`
/// (Android, iOS, and Google One Tap on the web). A provider whose client id
/// was not given at build time ([ProviderSignInConfig]) answers
/// [ProviderUnavailable], so its button keeps saying "coming soon"; nothing
/// here throws past the sign-in screen's error handling.
class PlatformProviderTokenSource implements ProviderTokenSource {
  PlatformProviderTokenSource({
    ProviderSignInConfig config = ProviderSignInConfig.fromEnvironment,
    bool? isWeb,
    TargetPlatform? platform,
    Duration webGoogleTimeout = const Duration(minutes: 2),
  }) : _config = config,
       _isWeb = isWeb,
       _platform = platform,
       _webGoogleTimeout = webGoogleTimeout;

  final ProviderSignInConfig _config;
  final bool? _isWeb;
  final TargetPlatform? _platform;
  final Duration _webGoogleTimeout;
  bool _googleReady = false;

  bool get _web => _isWeb ?? kIsWeb;
  TargetPlatform get _target => _platform ?? defaultTargetPlatform;

  @override
  Future<ProviderIdentityToken?> obtain(String provider) => switch (provider) {
    'apple' => _obtainApple(),
    'google' => _obtainGoogle(),
    _ => throw ArgumentError.value(provider, 'provider'),
  };

  Future<ProviderIdentityToken?> _obtainApple() async {
    if (!_config.appleAvailable(web: _web, platform: _target)) {
      throw const ProviderUnavailable('apple');
    }
    final native =
        !_web &&
        (_target == TargetPlatform.iOS || _target == TargetPlatform.macOS);
    final AuthorizationCredentialAppleID credential;
    try {
      if (native && !await SignInWithApple.isAvailable()) {
        throw const ProviderUnavailable('apple');
      }
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: native
            ? null
            : WebAuthenticationOptions(
                clientId: _config.appleServiceId,
                redirectUri: _config.appleRedirectUri!,
              ),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw ProviderUnavailable('apple', error);
    } on ProviderUnavailable {
      rethrow;
    } catch (error) {
      throw ProviderUnavailable('apple', error);
    }
    final token = credential.identityToken;
    if (token == null || token.isEmpty) {
      throw const ProviderUnavailable('apple', #noIdentityToken);
    }
    final name = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
    return ProviderIdentityToken(
      provider: 'apple',
      idToken: token,
      name: name.isEmpty ? null : name.join(' '),
    );
  }

  Future<ProviderIdentityToken?> _obtainGoogle() async {
    if (!_config.googleAvailable(web: _web, platform: _target)) {
      throw const ProviderUnavailable('google');
    }
    final signIn = GoogleSignIn.instance;
    try {
      if (!_googleReady) {
        if (_web) releaseGoogleSignInScript();
        await signIn.initialize(
          clientId: _config.googleClientIdFor(web: _web, platform: _target),
          serverClientId: _config.googleServerClientIdFor(
            web: _web,
            platform: _target,
          ),
        );
        _googleReady = true;
      }
      final GoogleSignInAccount? account;
      if (signIn.supportsAuthenticate()) {
        account = await signIn.authenticate();
      } else {
        account = await _googleWebOneTap(signIn);
        if (account == null) return null;
      }
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const ProviderUnavailable('google', #noIdentityToken);
      }
      return ProviderIdentityToken(
        provider: 'google',
        idToken: token,
        name: account.displayName,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw ProviderUnavailable('google', error);
    } on ProviderUnavailable {
      rethrow;
    } catch (error) {
      throw ProviderUnavailable('google', error);
    }
  }

  /// The web has no `authenticate()`: Google's One Tap prompt answers on
  /// the event stream. No answer in time (closed, or Google holds the
  /// prompt back after earlier closes) is the same as a closed sheet.
  Future<GoogleSignInAccount?> _googleWebOneTap(GoogleSignIn signIn) async {
    final event = signIn.authenticationEvents
        .where((e) => e is GoogleSignInAuthenticationEventSignIn)
        .cast<GoogleSignInAuthenticationEventSignIn>()
        .first
        .timeout(_webGoogleTimeout);
    final prompt = signIn.attemptLightweightAuthentication();
    if (prompt != null) unawaited(prompt.then((_) {}, onError: (_) {}));
    try {
      return (await event).user;
    } on TimeoutException {
      return null;
    }
  }
}
