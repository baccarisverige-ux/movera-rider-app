import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

GoogleMap _pumpedMap(WidgetTester tester) =>
    tester.widget<GoogleMap>(find.byType(GoogleMap));

void main() {
  test('no Map ID is baked in by default (plain test build)', () {
    expect(moveraGoogleMapId, isEmpty);
  });

  testWidgets('empty Map ID: no cloudMapId, Movera inline style kept', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomGoogleMap(cloudMapId: '')),
      ),
    );
    final map = _pumpedMap(tester);
    expect(map.cloudMapId, isNull);
    expect(map.style, moveraReferenceMapStyle);
  });

  testWidgets('Map ID set: cloudMapId passed, no inline style', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomGoogleMap(
            cloudMapId: '9fdc5d9e56d4a0916c77a424',
            customMapStyle: moveraReferenceMapStyle,
          ),
        ),
      ),
    );
    final map = _pumpedMap(tester);
    expect(map.cloudMapId, '9fdc5d9e56d4a0916c77a424');
    expect(map.style, isNull);
  });
}
