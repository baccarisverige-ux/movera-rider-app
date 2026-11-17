import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/native_maps_config.dart';
import 'package:movera_rider/core/web/web_maps_available.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Fast start round 5: the map is built the moment the Maps script says it
/// has loaded (its onload), not at the next 500 ms check.
void main() {
  testWidgets('the map replaces the placeholder at once on the ready '
      'signal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var hasKey = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeMapsConfig.channel,
      (call) async => hasKey,
    );
    void Function()? ready;
    CustomGoogleMap.debugWaitForMaps = true;
    CustomGoogleMap.onMapsReady = (cb) => ready = cb;
    addTearDown(() {
      CustomGoogleMap.debugWaitForMaps = null;
      CustomGoogleMap.onMapsReady = onGoogleMapsReady;
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
    expect(find.byKey(const ValueKey('map-unavailable')), findsOneWidget);
    expect(ready, isNotNull, reason: 'the map does not listen for the script');
    hasKey = true;
    await NativeMapsConfig.load();
    ready!();
    await tester.pump(const Duration(milliseconds: 16));
    debugDefaultTargetPlatformOverride = null;
    expect(
      find.byKey(const ValueKey('map-unavailable')),
      findsNothing,
      reason: 'the map waited for the next poll',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
