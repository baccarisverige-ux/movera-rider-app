import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/native_maps_config.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Audit phase 6 (map load failure): when the Maps engine never loads (no
/// network, a blocked or refused Maps script), the map placeholder said
/// nothing: the rider saw a blank grey area for good. After a wait it now
/// says the map is unavailable (en/fr/sv), and the map still replaces it
/// if the engine turns up later.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a map that never loads says it is unavailable', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var hasKey = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeMapsConfig.channel,
      (call) async => hasKey,
    );
    CustomGoogleMap.debugWaitForMaps = true;
    addTearDown(() {
      CustomGoogleMap.debugWaitForMaps = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeMapsConfig.channel,
        null,
      );
      NativeMapsConfig.debugReset();
    });
    await NativeMapsConfig.load();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    final message = find.byKey(const ValueKey('map-unavailable-message'));
    expect(find.byKey(const ValueKey('map-unavailable')), findsOneWidget);
    expect(message, findsNothing, reason: 'a slow load is not a failure');

    await tester.pump(CustomGoogleMap.mapsUnavailableAfter);
    expect(message, findsOneWidget);
    expect(
      find.text('Map unavailable. Check your connection, then reopen Movera.'),
      findsOneWidget,
    );

    hasKey = true;
    await NativeMapsConfig.load();
    debugDefaultTargetPlatformOverride = null;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('map-unavailable')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('C3: while the map waits it asks the page again every 5 s', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeMapsConfig.channel,
      (call) async => false,
    );
    var asks = 0;
    final request = CustomGoogleMap.requestMaps;
    CustomGoogleMap.requestMaps = () => asks++;
    CustomGoogleMap.debugWaitForMaps = true;
    addTearDown(() {
      CustomGoogleMap.requestMaps = request;
      CustomGoogleMap.debugWaitForMaps = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeMapsConfig.channel,
        null,
      );
      NativeMapsConfig.debugReset();
    });
    await NativeMapsConfig.load();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    expect(asks, 1);
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    // 15.5 s: asked at mount and again at 5, 10 and 15 s.
    expect(asks, 4);
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
  });
}
