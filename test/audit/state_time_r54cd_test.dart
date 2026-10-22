import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.4 parts c + d: state and time (low). One test per bug.
const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

/// An API whose every request is answered by [answer].
ApiClient _api(Future<http.Response> Function(http.Request request) answer) =>
    ApiClient(env: _env, client: MockClient(answer));

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// A ride searching since [startedAt].
RideSnapshot _searching(String rideId, DateTime startedAt) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: startedAt,
  searchStartedAt: startedAt,
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.33,
  pickupLng: 18.06,
  destinationLat: 59.34,
  destinationLng: 18.07,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

/// What [_finding] started; [_closeAll] stops it.
final _open = <void Function()>[];

void _closeAll() {
  FindingDriverController.active = null;
  for (final close in _open) {
    close();
  }
  _open.clear();
}

/// Starts a Finding controller for [rideId] searching since [startedAt],
/// reading the time from [now]. Widget tests call [_closeAll] at the end.
FindingDriverController _finding(
  ApiClient api,
  String rideId,
  DateTime startedAt, {
  DateTime Function()? now,
  void Function(RideStatus status)? onTerminal,
}) {
  final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
  final controller = FindingDriverController(
    realtime: realtime,
    ride: RideSession()..rideId = rideId,
    store: FindingDriverRepository(),
    api: api,
    now: now,
  );
  controller.start(
    snapshot: _searching(rideId, startedAt),
    onTick: (_) {},
    onMatched: () {},
    onTerminal: onTerminal ?? (_) {},
  );
  _open.addAll([controller.dispose, realtime.dispose]);
  return controller;
}

/// Waits (on the event loop, no fixed delay) until [done] holds.
Future<void> _until(bool Function() done, {int turns = 500}) async {
  for (var i = 0; i < turns && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition never held');
}

/// A restored search for [rideId] whose queued cancel (reason
/// plans_changed) the server check finds landed; returns once Finding
/// ended. Every POST path is added to [posts].
Future<FindingDriverController> _landedQueuedCancel(
  String rideId,
  List<String> posts,
) async {
  await PendingCancelStore.enqueue(
    rideId: rideId,
    reasonId: 'plans_changed',
    whileSearching: true,
  );
  // The restore's own flush gets no answer.
  unawaited(FindingDriverController.flushPendingCancels(
    api: _api((_) => Completer<http.Response>().future),
  ));
  addTearDown(FindingDriverController.abandonPendingCancelFlush);
  final ended = <RideStatus>[];
  final controller = _finding(
    _api((request) async {
      if (request.method == 'POST') posts.add(request.url.path);
      return request.url.path.endsWith('/$rideId')
          ? _json({
              'ride': {
                'id': rideId,
                'status': 'cancelled_by_rider',
                'version': 3,
              },
            })
          : _json({'code': 'OK', 'vehicles': []});
    }),
    rideId,
    DateTime.now().subtract(const Duration(minutes: 4)),
    onTerminal: ended.add,
  );
  await _until(() => ended.isNotEmpty);
  return controller;
}

/// A geocoder that records forward queries and finds a business for each.
class _RecordingGeocoder implements GeocodingRepository {
  final queries = <String>[];

  @override
  Future<PlaceResult?> forward(String query) async {
    queries.add(query);
    return const PlaceResult(
      address: 'Pickup Location AB, Malmö',
      point: GeoPoint(55.6, 13.0),
    );
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class _NoLocation extends Fake implements LocationRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });
  tearDown(_closeAll);

  testWidgets('rider-u94: after the app was paused the search time catches '
      'up on the next tick', (tester) async {
    var clock = DateTime(2026, 5, 4, 12);
    final controller = _finding(
      _api((_) async => _json({'code': 'OK', 'vehicles': []})),
      'ride_u94',
      clock.subtract(const Duration(seconds: 30)),
      now: () => clock,
    );
    // Four minutes in the background: no timer ran.
    clock = clock.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.elapsedSeconds, greaterThanOrEqualTo(270));
    expect(controller.stillLooking, isTrue);
    _closeAll();
  });

  test('rider-u100: a refused cancel resumes the search at its real elapsed '
      'time', () async {
    var clock = DateTime(2026, 5, 4, 12);
    final answer = Completer<http.Response>();
    final controller = _finding(
      _api((request) {
        if (request.url.path.endsWith('/cancel')) return answer.future;
        return Future.value(_json({'code': 'OK', 'vehicles': []}));
      }),
      'ride_u100',
      clock,
      now: () => clock,
    );
    final cancel = controller.cancelSearch();
    // Two minutes waiting on the cancel, then the server refuses it.
    clock = clock.add(const Duration(minutes: 2));
    answer.complete(_json({'code': 'invalid_transition'}, 422));
    expect(await cancel, SearchCancelResult.rejected);
    expect(controller.elapsedSeconds, greaterThanOrEqualTo(120));
  });

  test('rider-u95: a restored cancel the server check finds landed is filed '
      'as the rider\'s cancel', () async {
    await _landedQueuedCancel('ride_u95', []);
    final filed = (await OnDemandRideHistoryStore.read()).single;
    expect(filed.cancellationReason, 'plans_changed');
  });

  test('rider-u102: a reason given after a queued cancel landed is sent',
      () async {
    final posts = <String>[];
    final controller = await _landedQueuedCancel('ride_u102', posts);
    await controller.sendCancelReason('wait_too_long');
    expect(posts, contains('/api/v1/trips/ride_u102/cancel-reason'));
  });

  test('rider-u98: a cancel the outbox cannot store is still sent and does '
      'not jam Finding', () async {
    // Storage that throws on every outbox read and write.
    SharedPreferences.setMockInitialValues({'movera_pending_cancels': 'x'});
    var cancels = 0;
    final controller = _finding(
      _api((request) async {
        if (request.url.path.endsWith('/cancel')) {
          cancels++;
          return _json({'code': 'unavailable'}, 503);
        }
        return _json({'code': 'OK', 'vehicles': []});
      }),
      'ride_u98',
      DateTime.now(),
    );
    expect(await controller.cancelSearch(), SearchCancelResult.unsent);
    expect(cancels, greaterThan(0));
    expect(controller.cancelInFlight, isFalse);
  });

  test('rider-u104: a second cancel tap sends its own version and reason',
      () async {
    final first = await PendingCancelStore.enqueue(
      rideId: 'ride_u104',
      reasonId: 'plans_changed',
      expectedVersion: 3,
    );
    final again = await PendingCancelStore.enqueue(
      rideId: 'ride_u104',
      reasonId: 'driver_not_suitable',
      expectedVersion: 5,
    );
    expect(again.body(), {
      'reasonCode': 'driver_not_suitable',
      'reason': 'driver_not_suitable',
      'expectedVersion': 5,
    });
    expect(again.idempotencyKey, isNot(first.idempotencyKey));
    expect((await PendingCancelStore.find('ride_u104'))!.expectedVersion, 5);
  });

  testWidgets('rider-u105: the reason sheet offers the reasons the zone '
      'publishes', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final published = SeedRiderConfigRepository.seed.cancelReasons;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CancelReasonSheet(
          phase: CancelPhase.searching,
          committed: true,
          publishedReasons: published.map((r) => r.code),
        ),
      ),
    ));
    expect(find.text(L10n.current.cancelReasonPlansChanged), findsOneWidget);
    expect(find.text(L10n.current.cancelReasonWaitTooLong), findsNothing);
  });

  test('rider-39: placeholder pickup labels are not forward-geocoded',
      () async {
    final geocoder = _RecordingGeocoder();
    final home = HomeLocationController(
      location: _NoLocation(),
      geocoding: geocoder,
      motion: MotionEngine(),
    );
    addTearDown(home.dispose);
    final labels = [
      pickupLocationFallbackLabel,
      locationOffPickupLabel,
      droppedPinPickupAddress(const LatLng(59.31, 18.0686)),
    ];
    for (final label in labels) {
      expect(await home.normaliseAddress(label), label);
    }
    expect(geocoder.queries, isEmpty);
  });

  testWidgets('rider-u126: an older month read does not overwrite a newer '
      'one', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reads = <Completer<List<Reservation>>>[];
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeJourneySection(
              onDestinationTap: () {},
              onOpenSchedule: () {},
              ridesLoader: () => (reads..add(Completer())).last.future,
              clock: () => DateTime(2026, 10, 14, 12),
              changes: changes.stream,
            ),
          ),
        ),
      ),
    ));
    changes.add(null);
    await tester.pump();
    final ride = Reservation(
      reservationId: 'r1',
      createdAt: DateTime(2026, 10, 1),
      scheduledPickupAt: DateTime(2026, 10, 3, 8),
      pickup: const ReservationPlace(label: 'A'),
      destination: const ReservationPlace(label: 'B'),
      categoryId: 'economy',
      categoryName: 'Economy',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 200,
      currency: 'SEK',
      paymentMethod: 'Cash',
      status: ReservationStatus.completed,
    );
    reads[1].complete([ride]); // the newer read, after the ride was archived
    await tester.pump();
    reads[0].complete(const []);
    await tester.pump();
    expect(find.text('1 ride · 200 kr'), findsOneWidget);
  });

  test('rider-50: a push from the evening before a spring-forward morning '
      'says Yesterday', () {
    // The day after this zone's spring-forward (a 23-hour day), if any.
    var day = DateTime(2026, 1, 2);
    while (day.year == 2026 &&
        day.difference(DateTime(day.year, day.month, day.day - 1)) ==
            const Duration(days: 1)) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    if (day.year != 2026) day = DateTime(2026, 3, 30);
    final feed = NotificationsRepository(
      now: () => DateTime(day.year, day.month, day.day, 9),
    );
    feed.ingest(
      PushPayload(
        type: 'ride.driver_arrived',
        title: 'Driver arrived',
        sentAt: DateTime(day.year, day.month, day.day - 1, 23, 10),
      ),
      read: false,
    );
    expect(feed.all().single.time, L10n.current.notifYesterday('23:10'));
  });
}
