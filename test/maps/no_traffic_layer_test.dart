import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner, live test 2026-10-26 (N5): the green/red/yellow roads on the trip
/// map were Google's live traffic layer, not the Movera map style. The cloud
/// Map ID is the only styling: no map turns the traffic layer on, and the
/// shared map widget no longer even offers the switch.
void main() {
  test('no rider map enables the Google traffic layer', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('trafficEnabled: true')) offenders.add(entity.path);
    }
    expect(offenders, isEmpty);
  });

  test('CustomGoogleMap pins the traffic layer off instead of exposing it', () {
    final source = File(
      'lib/shared/widgets/custom_google_map.dart',
    ).readAsStringSync();
    expect(source, contains('trafficEnabled: false'));
    expect(source, isNot(contains('this.trafficEnabled')));
    expect(source, isNot(contains('widget.trafficEnabled')));
  });
}
