import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

/// proof5 (4) + owner 2026-11-07 (item 10): web/index.html armed the iOS
/// Motion & Orientation prompt on every page load, so the first tap of
/// any kind after each cold start asked for it. Now only the "my
/// position" tap asks (Home arms it from that tap).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'index.html: a plain tap asks nothing; "my position" asks once',
    () async {
      final run = await Process.run('node', [
        'test/web/heading_prompt_harness.js',
        'web/index.html',
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
      expect(out['plainTap'], 0, reason: 'prompt on a tap anywhere: $out');
      expect(out['afterMyPosition'], 1);
      expect(out['laterTap'], 1, reason: 'a later tap asked again: $out');
    },
  );

  HomeLocationController controller(List<String> log) => HomeLocationController(
    location: LocationRepository(),
    geocoding: AppGeocoding(),
    motion: MotionEngine(),
    startCompass: () async {
      log.add('start');
      return false;
    },
    readCompass: () => null,
    stopCompass: () {},
    armCompassPrompt: () => log.add('arm'),
  );

  test('Home start reads the compass without arming the prompt', () async {
    final log = <String>[];
    final ctl = controller(log);
    addTearDown(ctl.dispose);
    await ctl.startHeading(isMounted: () => true, onHeading: (_) {});
    expect(log, ['start']);
  });

  test('the "my position" tap arms the prompt', () async {
    final log = <String>[];
    final ctl = controller(log);
    addTearDown(ctl.dispose);
    await ctl.startHeading(
      isMounted: () => true,
      onHeading: (_) {},
      fromTap: true,
    );
    expect(log, ['arm', 'start']);
  });
}
