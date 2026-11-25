import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/auth/data/provider_sign_in_config.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/provider_token_source.dart';

// Owner 2026-11-23: real "Sign in with Google / Apple". The client ids come
// from build-time --dart-define; an empty one keeps "coming soon".
void main() {
  const empty = ProviderSignInConfig();
  const full = ProviderSignInConfig(
    googleWebClientId: ' web.apps.googleusercontent.com\n',
    googleIosClientId: 'ios.apps.googleusercontent.com ',
    googleServerClientId: '\tweb.apps.googleusercontent.com',
    appleServiceId: ' com.movera.rider.signin ',
    appleRedirectUri: 'https://example.org/auth/apple/callback\n',
  );

  test('no define compiled in: every provider off except native Apple', () {
    expect(ProviderSignInConfig.fromEnvironment.googleWebClientId, isEmpty);
    for (final web in [true, false]) {
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(empty.googleAvailable(web: web, platform: p), isFalse);
      }
    }
    expect(
      empty.appleAvailable(web: true, platform: TargetPlatform.iOS),
      isFalse,
    );
    expect(
      empty.appleAvailable(web: false, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      empty.appleAvailable(web: false, platform: TargetPlatform.iOS),
      isTrue,
    );
  });

  test('values are stripped of spaces and line breaks', () {
    expect(full.googleWebClientId, 'web.apps.googleusercontent.com');
    expect(full.googleIosClientId, 'ios.apps.googleusercontent.com');
    expect(full.appleServiceId, 'com.movera.rider.signin');
    expect(
      full.appleRedirectUri.toString(),
      'https://example.org/auth/apple/callback',
    );
    expect(
      const ProviderSignInConfig(
        appleServiceId: 'x',
        appleRedirectUri: 'http://a.b/c',
      ).appleAvailable(web: true, platform: TargetPlatform.linux),
      isFalse,
    );
  });

  test('which client id goes where', () {
    const ios = TargetPlatform.iOS;
    const android = TargetPlatform.android;
    expect(
      full.googleClientIdFor(web: true, platform: android),
      'web.apps.googleusercontent.com',
    );
    expect(full.googleServerClientIdFor(web: true, platform: android), isNull);
    expect(
      full.googleClientIdFor(web: false, platform: ios),
      'ios.apps.googleusercontent.com',
    );
    expect(
      full.googleServerClientIdFor(web: false, platform: ios),
      'web.apps.googleusercontent.com',
    );
    expect(full.googleClientIdFor(web: false, platform: android), isNull);
    expect(
      full.googleServerClientIdFor(web: false, platform: android),
      'web.apps.googleusercontent.com',
    );
    for (final web in [true, false]) {
      for (final p in [android, ios]) {
        expect(full.googleAvailable(web: web, platform: p), isTrue);
        expect(full.appleAvailable(web: web, platform: p), isTrue);
      }
    }
  });

  test(
    'empty ids: the real source says unavailable without opening an SDK',
    () async {
      for (final (web, p) in [
        (true, TargetPlatform.android),
        (false, TargetPlatform.android),
        (false, TargetPlatform.iOS),
      ]) {
        final source = PlatformProviderTokenSource(
          config: empty,
          isWeb: web,
          platform: p,
        );
        await expectLater(
          source.obtain('google'),
          throwsA(isA<ProviderUnavailable>()),
        );
        if (web || p == TargetPlatform.android) {
          await expectLater(
            source.obtain('apple'),
            throwsA(isA<ProviderUnavailable>()),
          );
        }
      }
    },
  );
  test('the sign-in controller uses the real source by default', () async {
    // Built without client ids (the test host is not iOS): still coming soon.
    await expectLater(
      AuthController().signIn(provider: 'google'),
      throwsA(isA<ProviderUnavailable>()),
    );
    expect(
      AuthController.defaultProviderTokens,
      isA<PlatformProviderTokenSource>(),
    );
  });
}
