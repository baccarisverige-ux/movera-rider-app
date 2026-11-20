import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/adjust_pickup.dart';
import 'package:movera_rider/features/active_ride/application/live_location_share.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_location_tools.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.144 (`contract.json#liveLocation`, owner 2026-11-20):
/// the adjust-pickup banner and the rider's "Share my location" switch.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  const pickup = GeoPoint(59.3300, 18.0600);
  // ~120 m north of the pickup.
  const away = GeoPoint(59.33108, 18.0600);

  group('settings', () {
    test('default OFF, 30 m, 8 s; a bad value is the default', () {
      expect(LiveLocationSettings.fromWire(null).share, isFalse);
      final read = LiveLocationSettings.fromWire({
        'share': true,
        'adjustPickupMeters': 45,
        'sendEverySeconds': 6,
      });
      expect(
        [read.share, read.adjustPickupMeters, read.sendEverySeconds],
        [true, 45, 6],
      );
      final bad = LiveLocationSettings.fromWire({
        'share': 'yes',
        'adjustPickupMeters': 9000,
        'sendEverySeconds': 2,
      });
      expect(
        [bad.share, bad.adjustPickupMeters, bad.sendEverySeconds],
        [false, 30, 8],
      );
    });
  });

  group('banner rule', () {
    test('searching: any distance over the threshold; under it, none', () {
      expect(
        AdjustPickup.metersToShow(
          phase: AdjustPickupPhase.searching,
          gps: away,
          pickup: pickup,
          thresholdMeters: 30,
        ),
        inInclusiveRange(118, 122),
      );
      expect(
        AdjustPickup.metersToShow(
          phase: AdjustPickupPhase.searching,
          gps: pickup,
          pickup: pickup,
          thresholdMeters: 30,
        ),
        isNull,
      );
    });
    test(
      'driver coming: only within maxPickupMoveMeters of the booked pickup',
      () {
        expect(
          AdjustPickup.metersToShow(
            phase: AdjustPickupPhase.driverComing,
            gps: away,
            pickup: pickup,
            thresholdMeters: 30,
            maxMoveMeters: 200,
          ),
          isNotNull,
        );
        expect(
          AdjustPickup.metersToShow(
            phase: AdjustPickupPhase.driverComing,
            gps: away,
            pickup: pickup,
            thresholdMeters: 30,
            maxMoveMeters: 100,
          ),
          isNull,
        );
        expect(
          AdjustPickup.metersToShow(
            phase: AdjustPickupPhase.driverComing,
            gps: away,
            pickup: pickup,
            thresholdMeters: 30,
          ),
          isNull,
        );
      },
    );
    test('a poor fix (over 50 m accuracy) is never offered', () {
      expect(
        AdjustPickup.metersToShow(
          phase: AdjustPickupPhase.searching,
          gps: away,
          pickup: pickup,
          thresholdMeters: 30,
          accuracyMeters: 80,
        ),
        isNull,
      );
    });
  });

  group('live frames', () {
    test('a LiveLocationEvent parses; a trip event does not', () {
      final frame = LiveLocationFrame.tryParse({
        'tripId': 'trp_1',
        'side': 'driver',
        'sharing': true,
        'lat': 59.3,
        'lng': 18.0,
        'at': '2026-11-20T10:00:00Z',
      });
      expect(
        [frame?.side, frame?.point?.latitude, frame?.point?.longitude],
        ['driver', 59.3, 18.0],
      );
      expect(
        LiveLocationFrame.tryParse({
          'eventId': 'e',
          'sequence': 2,
          'tripId': 'trp_1',
          'side': 'driver',
          'sharing': true,
          'at': '2026-11-20T10:00:00Z',
        }),
        isNull,
      );
    });
  });

  group('sender', () {
    test(
      'PUT live-location with the point; stop sends sharing false once; 409 live_location_off stops',
      () async {
        final bodies = <Map<String, Object?>>[];
        var refuse = false;
        final api = ApiClient(
          env: live,
          client: MockClient((request) async {
            expect(request.method, 'PUT');
            expect(request.url.path, '/api/v1/trips/trp_1/live-location');
            bodies.add(
              Map<String, Object?>.from(jsonDecode(request.body) as Map),
            );
            if (refuse) {
              return http.Response(
                jsonEncode({
                  'code': 'conflict',
                  'message': 'off',
                  'reason': 'live_location_off',
                }),
                409,
              );
            }
            return http.Response(
              jsonEncode({'sharing': true, 'sendEverySeconds': 8}),
              200,
            );
          }),
        );
        LiveShareStop? stopped;
        final sender = LiveLocationSender(
          api: api,
          tripId: 'trp_1',
          position: () async => away,
          every: const Duration(hours: 1),
          onStopped: (why) => stopped = why,
        );
        sender.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bodies.single, {
          'sharing': true,
          'lat': away.latitude,
          'lng': away.longitude,
        });
        await sender.stop();
        expect(bodies.last, {'sharing': false});
        expect(sender.running, isFalse);
        refuse = true;
        sender.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(stopped, LiveShareStop.zoneOff);
        expect(sender.running, isFalse);
      },
    );
  });

  group('widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required LiveLocationSettings settings,
      required AdjustPickupPhase phase,
      required Future<bool> Function(GeoPoint) onAdjust,
      ApiClient? api,
      bool bannerAllowed = true,
      void Function()? onFix,
      bool Function()? fixOk,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RideLocationTools(
              tripId: 'trp_1',
              phase: phase,
              pickup: pickup,
              maxMoveMeters: 200,
              driverName: 'Ali',
              settings: settings,
              api:
                  api ??
                  ApiClient(
                    env: live,
                    client: MockClient((_) async => http.Response('{}', 200)),
                  ),
              onAdjust: onAdjust,
              fix: () async {
                onFix?.call();
                if (fixOk != null && !fixOk()) return null;
                return (point: away, accuracyMeters: 5.0);
              },
              bannerAllowed: bannerAllowed,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'banner shows the distance; one tap moves the pickup to the GPS and hides it',
      (tester) async {
        GeoPoint? movedTo;
        await pump(
          tester,
          settings: const LiveLocationSettings(),
          phase: AdjustPickupPhase.driverComing,
          onAdjust: (to) async {
            movedTo = to;
            return true;
          },
        );
        expect(find.byKey(const Key('adjust-pickup-banner')), findsOneWidget);
        expect(find.textContaining('m from your pickup'), findsOneWidget);
        expect(
          find.byKey(const Key('share-location-card')),
          findsNothing,
          reason: 'zone switch default OFF',
        );
        await tester.tap(find.byKey(const Key('adjust-pickup-button')));
        await tester.pump();
        await tester.pump();
        expect(
          [movedTo?.latitude, movedTo?.longitude],
          [away.latitude, away.longitude],
        );
        expect(find.byKey(const Key('adjust-pickup-banner')), findsNothing);
        expect(find.text('Pickup moved to your location'), findsOneWidget);
      },
    );

    testWidgets(
      'zone ON while the driver comes: the share switch with the driver name and the privacy line',
      (tester) async {
        await pump(
          tester,
          settings: const LiveLocationSettings(share: true),
          phase: AdjustPickupPhase.driverComing,
          onAdjust: (_) async => false,
        );
        expect(find.text('Share my location'), findsOneWidget);
        expect(
          find.text('Ali sees exactly where you are. Stops at pickup.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Your live location is sent only to your driver until pickup and is not saved.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('searching: no share switch even when the zone is on', (
      tester,
    ) async {
      await pump(
        tester,
        settings: const LiveLocationSettings(share: true),
        phase: AdjustPickupPhase.searching,
        onAdjust: (_) async => false,
      );
      expect(find.byKey(const Key('share-location-card')), findsNothing);
      expect(find.byKey(const Key('adjust-pickup-banner')), findsOneWidget);
      unawaited(Future<void>.value());
    });

    testWidgets('driver arrived (pickup not editable): no banner', (
      tester,
    ) async {
      await pump(
        tester,
        settings: const LiveLocationSettings(),
        phase: AdjustPickupPhase.driverComing,
        bannerAllowed: false,
        onAdjust: (_) async => false,
      );
      expect(find.byKey(const Key('adjust-pickup-banner')), findsNothing);
    });

    testWidgets(
      '0 m = banner off; with sharing off too the GPS is not read at all',
      (tester) async {
        var reads = 0;
        await pump(
          tester,
          settings: const LiveLocationSettings(adjustPickupMeters: 0),
          phase: AdjustPickupPhase.driverComing,
          onAdjust: (_) async => false,
          onFix: () => reads++,
        );
        await tester.pump(const Duration(minutes: 2));
        expect(find.byKey(const Key('adjust-pickup-banner')), findsNothing);
        expect(reads, 0);
        expect(
          LiveLocationSettings.fromWire({
            'adjustPickupMeters': 0,
          }).adjustPickupMeters,
          0,
        );
        expect(
          LiveLocationSettings.fromWire({
            'adjustPickupMeters': 5,
          }).adjustPickupMeters,
          30,
        );
      },
    );

    testWidgets('banner only: the GPS is read every 30 s, not every 8 s', (
      tester,
    ) async {
      var reads = 0;
      await pump(
        tester,
        settings: const LiveLocationSettings(),
        phase: AdjustPickupPhase.searching,
        onAdjust: (_) async => false,
        onFix: () => reads++,
      );
      final first = reads;
      await tester.pump(const Duration(seconds: 61));
      expect(reads - first, 2);
    });

    testWidgets(
      'no permission / no fix: the switch goes back off and nothing is sent',
      (tester) async {
        var puts = 0;
        await pump(
          tester,
          settings: const LiveLocationSettings(share: true),
          phase: AdjustPickupPhase.driverComing,
          onAdjust: (_) async => false,
          fixOk: () => false,
          api: ApiClient(
            env: live,
            client: MockClient((_) async {
              puts++;
              return http.Response('{}', 200);
            }),
          ),
        );
        await tester.tap(find.byKey(const Key('share-location-switch')));
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<Switch>(find.byKey(const Key('share-location-switch')))
              .value,
          isFalse,
        );
        expect(puts, 0);
      },
    );

    testWidgets('a failed GPS read: the old fix is not sent again', (
      tester,
    ) async {
      var ok = true;
      final bodies = <Object?>[];
      await pump(
        tester,
        settings: const LiveLocationSettings(share: true),
        phase: AdjustPickupPhase.driverComing,
        onAdjust: (_) async => false,
        fixOk: () => ok,
        api: ApiClient(
          env: live,
          client: MockClient((r) async {
            bodies.add(jsonDecode(r.body));
            return http.Response('{}', 200);
          }),
        ),
      );
      await tester.tap(find.byKey(const Key('share-location-switch')));
      await tester.pump();
      await tester.pump();
      expect(bodies.where((b) => (b as Map)['sharing'] == true), hasLength(1));
      ok = false;
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 8));
      // At most one send can race the failed read (same 8 s tick); after
      // that nothing, however long the GPS stays silent.
      final afterFail = bodies
          .where((b) => (b as Map)['sharing'] == true)
          .length;
      expect(afterFail, lessThanOrEqualTo(2));
      await tester.pump(const Duration(seconds: 40));
      expect(
        bodies.where((b) => (b as Map)['sharing'] == true),
        hasLength(afterFail),
        reason: 'no stale re-send',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'app paused: sharing stops and reads pause; resumed: reads again, switch stays off',
      (tester) async {
        var reads = 0;
        final bodies = <Object?>[];
        await pump(
          tester,
          settings: const LiveLocationSettings(share: true),
          phase: AdjustPickupPhase.driverComing,
          onAdjust: (_) async => false,
          onFix: () => reads++,
          api: ApiClient(
            env: live,
            client: MockClient((r) async {
              bodies.add(jsonDecode(r.body));
              return http.Response('{}', 200);
            }),
          ),
        );
        final key = find.byKey(const Key('share-location-switch'));
        await tester.tap(key);
        await tester.pump();
        await tester.pump();
        expect(tester.widget<Switch>(key).value, isTrue);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        await tester.pump();
        expect(tester.widget<Switch>(key).value, isFalse);
        expect(bodies.last, {'sharing': false});
        final paused = reads;
        await tester.pump(const Duration(minutes: 2));
        expect(reads, paused, reason: 'no GPS while away');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(reads, greaterThan(paused));
        expect(tester.widget<Switch>(key).value, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
