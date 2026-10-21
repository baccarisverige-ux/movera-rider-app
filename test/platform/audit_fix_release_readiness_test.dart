import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/native_maps_config.dart';
import 'package:movera_rider/core/web/web_maps_available.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

String _read(String path) => File(path).readAsStringSync();

/// Share of pixels close to the Movera logo blue (#026ED9).
Future<double> _brandBlueShare(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var blue = 0;
  final pixels = image.width * image.height;
  for (var i = 0; i < pixels; i++) {
    final r = data.getUint8(i * 4);
    final g = data.getUint8(i * 4 + 1);
    final b = data.getUint8(i * 4 + 2);
    if ((r - 2).abs() < 30 && (g - 110).abs() < 30 && (b - 217).abs() < 30) {
      blue += 1;
    }
  }
  image.dispose();
  return blue / pixels;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CODE-1 iOS Maps key', () {
    test(
      'Info.plist exposes GMSApiKey from the GOOGLE_MAPS_API_KEY setting',
      () {
        final plist = _read('ios/Runner/Info.plist');
        expect(plist, contains('<key>GMSApiKey</key>'));
        expect(plist, contains(r'<string>$(GOOGLE_MAPS_API_KEY)</string>'));
      },
    );

    test('Debug and Release xcconfigs include the untracked secrets file', () {
      for (final name in ['Debug', 'Release']) {
        expect(
          _read('ios/Flutter/$name.xcconfig'),
          contains('#include? "Secrets.xcconfig"'),
          reason: name,
        );
      }
      expect(File('ios/Flutter/Secrets.xcconfig.example').existsSync(), isTrue);
      expect(_read('.gitignore'), contains('ios/Flutter/Secrets.xcconfig'));
    });

    test('a release build without the key fails in an Xcode build phase', () {
      final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbx, contains('/* Check Google Maps key */,'));
      expect(
        pbx,
        contains(
          r'GOOGLE_MAPS_API_KEY is not set for this ${CONFIGURATION} build',
        ),
      );
      expect(pbx, contains(r'exit 1'));
    });

    test('AppDelegate reads GMSApiKey and reports it to Dart', () {
      final swift = _read('ios/Runner/AppDelegate.swift');
      expect(swift, contains('forInfoDictionaryKey: "GMSApiKey"'));
      expect(swift, contains('"movera/maps_config"'));
      expect(swift, contains('"hasGoogleMapsKey"'));
    });

    testWidgets(
      'iOS without a key shows the no-map fallback, not a GoogleMap',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeMapsConfig.channel,
          (call) async => call.method == 'hasGoogleMapsKey' ? false : null,
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            NativeMapsConfig.channel,
            null,
          );
          NativeMapsConfig.debugReset();
        });
        await NativeMapsConfig.load();
        expect(googleMapsAvailable(), isFalse);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
        );
        expect(find.byKey(const ValueKey('map-unavailable')), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    test('iOS with a key and Android keep the map', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        NativeMapsConfig.channel,
        (call) async => true,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await NativeMapsConfig.load();
      expect(googleMapsAvailable(), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await NativeMapsConfig.load();
      expect(googleMapsAvailable(), isTrue);
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(NativeMapsConfig.channel, null);
      NativeMapsConfig.debugReset();
    });
  });

  test('CODE-15 Android release build fails without MAPS_API_KEY', () {
    final gradle = _read('android/app/build.gradle.kts');
    expect(gradle, contains('if (packagesRelease && !hasMapsApiKey)'));
    expect(gradle, contains('Release builds require a Google Maps key'));
    final workflow = _read('.github/workflows/android-release-signing.yml');
    expect(workflow, contains(r'MAPS_API_KEY: ${{ secrets.MAPS_API_KEY'));
  });

  test('rider-u206: iOS keeps Safety audio recording in the background', () {
    final plist = _read('ios/Runner/Info.plist');
    final modes = RegExp(
      r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(modes, isNotNull);
    expect(modes!.group(1), contains('<string>audio</string>'));
  });

  group('CODE-8 store blockers', () {
    test('location purpose string is specific and when-in-use only', () {
      final plist = _read('ios/Runner/Info.plist');
      expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
      expect(
        plist,
        isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
      );
      expect(plist, isNot(contains('This app needs access to location')));
      expect(
        RegExp(
          r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>Movera[^<]*pickup',
        ).hasMatch(plist),
        isTrue,
      );
      expect(plist, isNot(contains('<string>fetch</string>')));
    });

    test('no broad Android storage permission', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
      expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    });

    testWidgets('launcher icons carry the Movera pin, not the Flutter logo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final path in [
          'web/icons/Icon-192.png',
          'web/icons/Icon-maskable-512.png',
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        ]) {
          expect(await _brandBlueShare(path), greaterThan(0.05), reason: path);
        }
      });
      // App Store icons must have no alpha channel (PNG colour type 2 = RGB).
      final ios = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      ).readAsBytesSync();
      expect(ios[25], 2);
    });
  });

  test('CODE-9 only the com.movera.rider MainActivity remains', () {
    final activities = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('MainActivity.kt'))
        .toList();
    expect(activities, hasLength(1));
    expect(_read(activities.single.path), contains('package com.movera.rider'));
  });

  group('CODE-7 web push service worker', () {
    test('a firebase-messaging-sw.js ships and is inert without Firebase', () {
      final sw = _read('web/firebase-messaging-sw.js');
      expect(sw, contains("addEventListener('push'"));
      expect(sw, isNot(contains('importScripts')));
      final push = _read('lib/core/notifications/firebase_push_service.dart');
      expect(push, contains('serviceWorkerScriptPath:'));
      expect(push, contains("'firebase-messaging-sw.js'"));
    });

    test('index.html keeps the Firebase worker when it removes old ones', () {
      final html = _read('web/index.html');
      expect(html, contains("indexOf('firebase-messaging-sw.js') === -1"));
    });
  });

  test('CODE-2 the RideCheck simulator is installed only behind the QA gate', () {
    final html = _read('web/index.html');
    expect(html, isNot(contains('window.moveraSimulateRideCheck =')));
    expect(html, isNot(contains('_moveraPendingRideCheck')));
    final hooks = _read('lib/core/debug/web_qa_hooks_web.dart');
    final install = hooks.substring(
      hooks.indexOf('void installRideCheckQaHook()'),
    );
    expect(
      install.substring(0, install.indexOf('globalContext')),
      contains('if (!moveraQaHooksEnabled) return;'),
    );
    final pending = hooks.substring(
      hooks.indexOf('String? pendingRideCheckType()'),
    );
    expect(
      pending.substring(0, pending.indexOf('globalContext')),
      contains('if (!moveraQaHooksEnabled) return null;'),
    );
    final bootstrap = _read('lib/app/bootstrap.dart');
    expect(
      RegExp(
        r'if \(moveraQaHooksEnabled\) \{\s*registerWebQaHooks\(\);\s*installRideCheckQaHook\(\);',
      ).hasMatch(bootstrap),
      isTrue,
    );
  });
}
