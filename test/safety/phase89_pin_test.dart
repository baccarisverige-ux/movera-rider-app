import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/pin_composition.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';

void main() {
  test(
    'missing, malformed and mock PINs cannot pass for server-issued PINs',
    () {
      expect(RidePin.fromJson(null).isAvailable, isFalse);
      expect(RidePin.fromJson({'pin': '123'}).pin, isEmpty);
      expect(RidePin.fromJson({'pin': '12345'}).pin, isEmpty);
      expect(RidePin.fromJson({'pin': '1234'}).serverAuthoritative, isFalse);
      expect(
        RidePin.fromJson({
          'pin': '1234',
          'serverAuthoritative': false,
        }).serverAuthoritative,
        isFalse,
      );
    },
  );

  test('mock PIN issuance is rejected by release composition', () {
    for (final flavor in [AppFlavor.production, AppFlavor.staging]) {
      final env = AppEnv(flavor: flavor, apiBaseUrl: 'https://example.test');
      expect(
        () => PinComposition.validate(
          environment: env,
          usesMockPinIssuance: true,
        ),
        throwsStateError,
      );
      PinComposition.validate(environment: env, usesMockPinIssuance: false);
    }
  });

  test('offline load discards previously cached PIN digits', () async {
    final local = PreferencesSafetyLocalDataSource(memoryOnly: true);
    final cache = SafetyCache(
      pin: RidePin.fromJson({
        'pinId': 'stale',
        'pin': '1234',
        'serverAuthoritative': true,
      }),
    );
    await local.save(cache);
    final store = SafetyStore(local: local, remote: _OfflinePinRemote());
    await store.load();
    expect(store.pin.pin, isEmpty);
  });

  testWidgets('PIN row fits a 320 pixel display', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SafetyPinCadre(pin: '1234', caption: 'Show to driver'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('4'), findsOneWidget);
  });
}

class _OfflinePinRemote extends ApiSafetyRemoteDataSource {
  _OfflinePinRemote() : super(ApiClient(client: InProcessMockClient()));

  @override
  Future<RidePin> getPin() async => throw StateError('offline');
}
