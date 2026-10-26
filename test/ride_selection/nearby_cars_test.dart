import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/application/nearby_cars_controller.dart';
import 'package:movera_rider/features/ride_selection/data/nearby_cars_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';

/// Owner round 2 (contract v0.5.2 §13): the free cars around the pickup on
/// Select ride, gliding between the server's answers.

class _FakeSource implements NearbyCarsSource {
  final answers = <Completer<NearbyCarsAnswer>>[];
  final asked = <GeoPoint>[];

  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) {
    asked.add(point);
    final next = Completer<NearbyCarsAnswer>();
    answers.add(next);
    return next.future;
  }

  void answer(List<NearbyCar> cars, {int refreshSeconds = 5}) =>
      answers.last.complete(
        NearbyCarsAnswer(
          cars: cars,
          refresh: Duration(seconds: refreshSeconds),
        ),
      );

  void fail() => answers.last.completeError(StateError('offline'));
}

const _sergels = GeoPoint(59.3326, 18.0649);

NearbyCar _car(String key, double lat, double lng, {double? heading}) =>
    NearbyCar(key: key, latitude: lat, longitude: lng, heading: heading);

void main() {
  group('the answer', () {
    test('keeps only what is needed, at most 15 cars, each key once', () {
      final answer = NearbyCarsRepository.parse({
        'items': [
          for (var i = 0; i < 20; i++)
            {
              'key': 'car-$i',
              'lat': 59.33 + i / 1000,
              'lng': 18.06,
              'heading': 450,
              'driverId': 'drv_secret',
            },
          {'key': 'car-0', 'lat': 1, 'lng': 1},
        ],
        'refreshSeconds': 5,
      });
      expect(answer.cars, hasLength(15));
      expect(answer.cars.map((c) => c.key).toSet(), hasLength(15));
      expect(answer.cars.first.heading, 90);
      expect(answer.refresh, const Duration(seconds: 5));
    });

    test('drops broken cars and keeps the refresh between 3 and 30 s', () {
      final answer = NearbyCarsRepository.parse({
        'items': [
          {'key': '', 'lat': 59, 'lng': 18},
          {'key': 'a', 'lat': 91, 'lng': 18},
          {'key': 'b', 'lat': 'x', 'lng': 18},
          {'key': 'c', 'lat': 59.1, 'lng': 18.1},
          'nonsense',
        ],
        'refreshSeconds': 0.5,
      });
      expect(answer.cars.map((c) => c.key), ['c']);
      expect(answer.cars.single.heading, isNull);
      expect(answer.refresh, NearbyCarsRepository.minRefresh);
      expect(
        NearbyCarsRepository.parse({'refreshSeconds': 600}).refresh,
        NearbyCarsRepository.maxRefresh,
      );
      expect(
        NearbyCarsRepository.parse({}).refresh,
        NearbyCarsRepository.defaultRefresh,
      );
      expect(NearbyCarsRepository.parse({}).cars, isEmpty);
    });

    test('live stability: the cars are asked for at most every 5 s', () {
      // The live server is small; the cars are decoration and must not
      // compete with the trip calls. Whatever the server says, the app
      // keeps to 5-8 s between requests.
      expect(NearbyCarsRepository.minRefresh, const Duration(seconds: 5));
      expect(
        NearbyCarsRepository.defaultRefresh.inSeconds,
        inInclusiveRange(5, 8),
      );
      expect(
        NearbyCarsRepository.parse({'refreshSeconds': 1}).refresh,
        const Duration(seconds: 5),
      );
      expect(
        NearbyCarsRepository.parse({'refreshSeconds': 0.3}).refresh,
        const Duration(seconds: 5),
      );
    });
  });

  group('the controller', () {
    testWidgets(
      'asks for the pickup, then again after refreshSeconds, never twice at once',
      (tester) async {
        final source = _FakeSource();
        final cars = NearbyCarsController(source: source);
        cars.watch(_sergels);
        cars.watch(_sergels);
        expect(source.asked, hasLength(1));
        await tester.pump(const Duration(seconds: 10));
        expect(
          source.asked,
          hasLength(1),
          reason: 'the first answer is still on its way',
        );
        source.answer([_car('a', 59.333, 18.065)], refreshSeconds: 4);
        await tester.pump();
        expect(cars.frames().single.key, 'a');
        await tester.pump(const Duration(seconds: 3));
        expect(source.asked, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(source.asked, hasLength(2));
        cars.dispose();
      },
    );

    testWidgets('a car glides to its new place; a far jump is drawn at once', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 25, 9);
      final source = _FakeSource();
      final cars = NearbyCarsController(
        source: source,
        clock: () => now,
        glide: const Duration(seconds: 1),
      );
      cars.watch(_sergels);
      source.answer([_car('a', 59.3300, 18.0600), _car('b', 59.3300, 18.0600)]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      source.answer([_car('a', 59.3310, 18.0600), _car('b', 59.4300, 18.0600)]);
      await tester.pump();
      // Halfway through the glide, `a` is halfway; `b` (11 km away) is there.
      now = now.add(const Duration(milliseconds: 500));
      final half = {for (final f in cars.frames()) f.key: f};
      expect(half['a']!.latitude, closeTo(59.3305, 0.00001));
      expect(half['b']!.latitude, 59.4300);
      expect(cars.gliding(), isTrue);
      now = now.add(const Duration(milliseconds: 600));
      expect({for (final f in cars.frames()) f.key: f}['a']!.latitude, 59.3310);
      expect(cars.gliding(), isFalse);
      // No heading from the server: it points where the car went (north).
      expect(
        {for (final f in cars.frames()) f.key: f}['a']!.heading,
        closeTo(0, 0.5),
      );
      cars.dispose();
    });

    testWidgets('a car missing from the next answer is gone', (tester) async {
      final source = _FakeSource();
      final cars = NearbyCarsController(source: source);
      cars.watch(_sergels);
      source.answer([_car('a', 59.33, 18.06), _car('b', 59.34, 18.06)]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      source.answer([_car('b', 59.34, 18.06)]);
      await tester.pump();
      expect(cars.frames().map((f) => f.key), ['b']);
      cars.dispose();
    });

    testWidgets(
      'a failure keeps the cars and asks again later, slower each time',
      (tester) async {
        final source = _FakeSource();
        final cars = NearbyCarsController(source: source);
        cars.watch(_sergels);
        source.answer([_car('a', 59.33, 18.06)]);
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        source.fail();
        await tester.pump();
        expect(cars.frames(), hasLength(1));
        await tester.pump(const Duration(seconds: 4));
        expect(source.asked, hasLength(2));
        await tester.pump(const Duration(seconds: 1));
        expect(source.asked, hasLength(3));
        source.fail();
        await tester.pump();
        await tester.pump(const Duration(seconds: 9));
        expect(source.asked, hasLength(3));
        await tester.pump(const Duration(seconds: 1));
        expect(source.asked, hasLength(4));
        cars.dispose();
      },
    );

    testWidgets(
      'pause stops asking; resume asks at once; dispose stops for good',
      (tester) async {
        final source = _FakeSource();
        final cars = NearbyCarsController(source: source);
        cars.watch(_sergels);
        source.answer(const []);
        await tester.pump();
        cars.pause();
        await tester.pump(const Duration(minutes: 1));
        expect(source.asked, hasLength(1));
        cars.resume();
        expect(source.asked, hasLength(2));
        source.answer(const []);
        await tester.pump();
        cars.dispose();
        await tester.pump(const Duration(minutes: 1));
        expect(source.asked, hasLength(2));
      },
    );

    testWidgets('a pickup far away starts over and asks for the new place', (
      tester,
    ) async {
      final source = _FakeSource();
      final cars = NearbyCarsController(source: source);
      cars.watch(_sergels);
      source.answer([_car('a', 59.333, 18.065)]);
      await tester.pump();
      const sodertalje = GeoPoint(59.1955, 17.6253);
      cars.watch(sodertalje);
      expect(cars.frames(), isEmpty);
      expect(source.asked.last, sodertalje);
      cars.dispose();
    });
  });

  group('the demo cars', () {
    test(
      'seven cars near the point, rounded, with day-stable keys, moving',
      () {
        final t0 = DateTime.utc(2026, 10, 25, 9);
        final first = InProcessMockClient.demoNearbyCars(59.3326, 18.0649, t0);
        final later = InProcessMockClient.demoNearbyCars(
          59.3326,
          18.0649,
          t0.add(const Duration(seconds: 5)),
        );
        expect(first, hasLength(7));
        expect(first.map((c) => c['key']), later.map((c) => c['key']));
        for (final car in first) {
          expect(car.keys.toSet(), {'key', 'lat', 'lng', 'heading'});
          final lat = car['lat'] as double;
          expect(lat, double.parse(lat.toStringAsFixed(4)));
          expect((lat - 59.3326).abs(), lessThan(0.03));
          final heading = car['heading'] as double;
          expect(heading, inInclusiveRange(0, 360));
        }
        var moved = 0;
        for (var i = 0; i < 7; i++) {
          if (first[i]['lat'] != later[i]['lat'] ||
              first[i]['lng'] != later[i]['lng']) {
            moved++;
          }
        }
        expect(moved, greaterThan(3));
      },
    );
  });

  group('the car on the map', () {
    test(
      'faces right going east, is mirrored going west, and tilts at most 25°',
      () {
        expect(NearbyCarMarker.pose(null), (mirrored: false, rotation: 0.0));
        expect(NearbyCarMarker.pose(90), (mirrored: false, rotation: 0.0));
        expect(NearbyCarMarker.pose(270), (mirrored: true, rotation: 0.0));
        expect(NearbyCarMarker.pose(60), (mirrored: false, rotation: -25.0));
        expect(NearbyCarMarker.pose(100), (mirrored: false, rotation: 10.0));
        expect(NearbyCarMarker.pose(300), (mirrored: true, rotation: 25.0));
        expect(NearbyCarMarker.pose(-90), (mirrored: true, rotation: 0.0));
      },
    );
  });
}
