import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/constants/app_version.dart' as build;
import 'package:movera_rider/core/content/rider_content.dart';

/// Contract v0.18.154 P16c (`contract.json#appUpdate`; owner 2026-11-21
/// "Yes, build it now (Recommended)"): the zone's minimum app version per
/// platform (`RiderAppConfig.appUpdate.minVersion { android, ios }`, null =
/// off) and its store links (`appUpdate.storeUrls`, null = the built-in
/// link). Below it the app shows one full screen "Update Movera to
/// continue", never while a ride is live (the block at Home after it).
@immutable
class MinAppVersionRule {
  const MinAppVersionRule({
    this.minVersion = const {},
    this.storeUrls = const {},
  });

  static const off = MinAppVersionRule();
  static final _semver = RegExp(r'^\d+\.\d+\.\d+$');

  /// Platform (`android`, `ios`) → minimum x.y.z.
  final Map<String, String> minVersion;

  /// Platform → https store link.
  final Map<String, String> storeUrls;

  /// `RiderAppConfig.appUpdate`; anything not valid reads as off. The older
  /// keys (minimumVersion, latestVersion, storeUrl) never block.
  factory MinAppVersionRule.fromJson(Object? appUpdate) {
    if (appUpdate is! Map) return off;
    final mins = appUpdate['minVersion'];
    final urls = appUpdate['storeUrls'];
    return MinAppVersionRule(
      minVersion: {
        if (mins is Map)
          for (final platform in MinAppVersion.platforms)
            if (mins[platform] case final String v when _semver.hasMatch(v))
              platform: v,
      },
      storeUrls: {
        if (urls is Map)
          for (final platform in MinAppVersion.platforms)
            if (urls[platform] case final String url
                when url.startsWith('https://'))
              platform: url,
      },
    );
  }

  /// True when [running] on [platform] is below this rule's minimum.
  bool blocks(String? running, String? platform) {
    if (running == null || platform == null) return false;
    return versionBelow(running, minVersion[platform]);
  }
}

/// The rule in use and the build this phone runs.
abstract final class MinAppVersion {
  static const platforms = ['android', 'ios'];

  /// The rule of the zone the app follows (config start and every
  /// `config_published`).
  static final ValueNotifier<MinAppVersionRule> rule = ValueNotifier(
    MinAppVersionRule.off,
  );

  /// The server answered 426 `app_update_required`; cleared by the next
  /// document.
  static final ValueNotifier<bool> serverSaid = ValueNotifier(false);

  /// The rule of the document in use. [fresh]: a document the server just
  /// sent, which also ends a 426 block (the server's rule is in it).
  static void accept(Object? appUpdate, {bool fresh = true}) {
    rule.value = MinAppVersionRule.fromJson(appUpdate);
    if (fresh) serverSaid.value = false;
  }

  /// A 426 answer with reason `app_update_required`.
  static void markServerSaid(Map<String, dynamic>? body) {
    if (body != null && body['reason'] != 'app_update_required') return;
    serverSaid.value = true;
  }

  @visibleForTesting
  static void reset() {
    rule.value = MinAppVersionRule.off;
    serverSaid.value = false;
  }

  /// This build's version x.y.z (`MOVERA_APP_VERSION`); null for a local
  /// ("dev") build, which is never blocked and sends no header.
  static String? running = _plain(build.appVersion);

  static String? _plain(String raw) {
    final core = raw.trim().split('+').first;
    return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(core) ? core : null;
  }

  /// `android` / `ios`; null on the web and other platforms (no check).
  static String? platform = _platform();

  static String? _platform() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  /// `X-App-Version` + `X-App-Platform`, only on an Android / iOS build
  /// with a version (`contract.json#appUpdate.headers`).
  static Map<String, String> get headers {
    final version = running;
    final on = platform;
    if (version == null || on == null) return const {};
    return {'X-App-Version': version, 'X-App-Platform': on};
  }

  /// True when this phone must update (the rule or the server says so).
  static bool get required {
    if (running == null || platform == null) return false;
    return serverSaid.value || rule.value.blocks(running, platform);
  }

  /// The store link for this phone: the zone's, else [fallback].
  static Uri storeUri(String fallback) {
    final on = platform;
    return Uri.parse(
      (on == null ? null : rule.value.storeUrls[on]) ?? fallback,
    );
  }
}
