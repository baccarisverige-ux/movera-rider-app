// Live 5+5 test 2026-11-08 (/admin/errors "rider ImageCodecException", 56 ->
// 61): the staging test drivers' approved profile_photo is 1124 bytes,
// Content-Type image/jpeg, starting ffd8ffe0 and then the text
// "movera-big-test-placeholder-" repeated (no real JPEG). The avatar must
// keep the Movera fallback and report no crash.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_photo.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';

const path = '/api/v1/rider/trips/trp_1/driver-photo';

Uint8List fakeJpeg() {
  final b = BytesBuilder()..add([0xff, 0xd8, 0xff, 0xe0]);
  final filler = utf8.encode('movera-big-test-placeholder-');
  while (b.length < 1124) {
    b.add(filler);
  }
  return Uint8List.fromList(b.toBytes().sublist(0, 1124));
}

void main() {
  tearDown(() {
    DriverPhotos.clear();
    DriverPhotos.debugApi = null;
  });

  testWidgets('a photo that does not decode keeps the Movera avatar and '
      'reports nothing', (tester) async {
    final tokens = MemoryTokenStore();
    await tester.runAsync(() => tokens.save(access: 'a', refresh: 'r'));
    DriverPhotos.debugApi = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.test.movera.invalid',
      ),
      tokens: tokens,
      client: MockClient(
        (_) async => http.Response.bytes(
          fakeJpeg(),
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      ),
    );
    await tester.runAsync(() => DriverPhotos.load(path));
    await tester.pumpWidget(
      const MaterialApp(
        home: DriverPhotoAvatar(
          driver: MatchedDriver(id: 'd', firstName: 'Sara', photoUrl: path),
          radius: 22,
          fallback: Text('S'),
        ),
      ),
    );
    // Let the engine try to decode the bytes.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    final error = tester.takeException();
    expect(error, isNull, reason: 'reported to FlutterError: $error');
    expect(find.text('S'), findsOneWidget);
    expect(find.byKey(const ValueKey('driver-photo-server')), findsNothing);
    // The bad photo is not tried again by the next avatar of this trip.
    expect(DriverPhotos.cached(path), isNull);
    expect(await tester.runAsync(() => DriverPhotos.load(path)), isNull);
  });
}
