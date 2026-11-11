import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/home/application/home_presence.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/ride_selection/application/nearby_cars_controller.dart';

/// Global plan step 62 (T3): counts every request the rider app sends while
/// it sits in one state. Each state runs the app's real request owners
/// (the classes that hold the timers and streams) over one real
/// [ApiClient], whose `http.Client` is [CountingClient]; time is a fake
/// clock. Nothing in `lib/` is changed for this.
const tripId = 'trp_budget';
const _live = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://budget.invalid',
);

/// The rider app's main states (what runs in each is in [_enter]).
enum RiderState {
  homeIdle,
  quoting,
  searching,
  driverArriving,
  onTrip,
  tripFinished,
  background,

  /// Home with `/rider/config/stream` refused (server down / restarting).
  homeConfigStreamDown,

  /// Driver arriving with the trip stream refused (poll fallback).
  arrivingTripStreamDown,
}

/// One request: `METHOD path`, ids and query values folded so the same
/// endpoint always gets the same key.
String endpointKey(http.BaseRequest request) {
  final uri = request.url;
  var path = uri.path.replaceAll(tripId, '{tripId}');
  if (path == '/api/v1/rider/trips') {
    final q = uri.queryParametersAll;
    final kind = q['kind']?.join(',') ?? '';
    final status = q['status']?.join(',');
    path += status == null ? '?kind=$kind' : '?kind=$kind&status=$status';
  }
  final sse = request.headers['Accept'] == 'text/event-stream';
  return '${request.method} $path${sse ? ' (SSE open)' : ''}';
}

/// The fake server: answers each request, keeps SSE streams open with a
/// heartbeat every 15 s, and counts.
class CountingClient extends http.BaseClient {
  CountingClient({this.refuseStream = const {}});

  /// Path prefixes whose SSE open is refused with a 503.
  final Set<String> refuseStream;
  final List<({Duration at, String key})> sent = [];
  final List<StreamController<List<int>>> _open = [];
  Duration Function() now = () => Duration.zero;
  String tripStatus = 'searching';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = endpointKey(request);
    sent.add((at: now(), key: key));
    final path = request.url.path;
    if (request.headers['Accept'] == 'text/event-stream') {
      if (refuseStream.any(path.startsWith)) {
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
      }
      late final Timer beat;
      final controller = StreamController<List<int>>(
        onCancel: () => beat.cancel(),
      );
      beat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!controller.isClosed) controller.add(utf8.encode(': hb\n'));
      });
      _open.add(controller);
      return http.StreamedResponse(controller.stream, 200);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(_answer(path)))),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  Map<String, Object?> _answer(String path) {
    if (path.endsWith('/messages')) return {'items': <Object>[]};
    if (path == '/api/v1/rider/trips') return {'items': <Object>[]};
    if (path.startsWith('/api/v1/trips/')) {
      return {
        'tripId': tripId,
        'status': tripStatus,
        'version': 1,
        'updatedAt': '2026-11-10T09:00:00Z',
      };
    }
    if (path == '/api/v1/rider/nearby-vehicles') {
      // contract.json#riderNearby.refreshSeconds.
      return {'vehicles': <Object>[], 'refreshSeconds': 5};
    }
    return {};
  }

  void closeAll() {
    for (final c in _open) {
      if (!c.isClosed) unawaited(c.close());
    }
  }
}

class _MemoryConfigCache implements RiderConfigCache {
  @override
  Future<Map<String, Object?>?> read(String zoneId) async => null;
  @override
  Future<void> write(String zoneId, Map<String, Object?> document) async {}
}

/// What one state sent: requests per minute per endpoint (steady part) and
/// the requests sent in the first second (the entry burst).
class StateMeasure {
  StateMeasure(this.state, this.perMinute, this.onEntry);
  final RiderState state;
  final Map<String, double> perMinute;
  final Map<String, int> onEntry;
  double get total => perMinute.values.fold(0, (a, b) => a + b);
}

/// Steady window: minutes 1..11 after entering the state (10 minutes).
const warmUp = Duration(minutes: 1);
const window = Duration(minutes: 10);

/// Runs [state] for [warmUp] + [window] on a fake clock and counts.
/// [extra] is a seam for the Rule 35 proof only (an added poll).
StateMeasure measure(
  RiderState state, {
  void Function(ApiClient api, List<void Function()> stops)? extra,
}) {
  late StateMeasure result;
  fakeAsync((async) {
    final client = CountingClient(
      refuseStream: switch (state) {
        RiderState.homeConfigStreamDown => {'/api/v1/rider/config/stream'},
        RiderState.arrivingTripStreamDown => {'/api/v1/trips/'},
        _ => const {},
      },
    )..now = () => async.elapsed;
    final api = ApiClient(client: client, env: _live);
    final stops = <void Function()>[];
    _enter(state, api, client, stops);
    extra?.call(api, stops);
    async.elapse(warmUp + window);
    for (final stop in stops.reversed) {
      stop();
    }
    client.closeAll();
    async.flushMicrotasks();
    async.elapse(const Duration(minutes: 2));

    final perMinute = <String, double>{};
    final onEntry = <String, int>{};
    for (final r in client.sent) {
      if (r.at < const Duration(seconds: 1)) {
        onEntry[r.key] = (onEntry[r.key] ?? 0) + 1;
      }
      if (r.at >= warmUp && r.at < warmUp + window) {
        perMinute[r.key] = (perMinute[r.key] ?? 0) + 1 / window.inMinutes;
      }
    }
    result = StateMeasure(state, perMinute, onEntry);
  });
  return result;
}

/// What the app runs in each state (file references in
/// docs/request-budgets.md).
void _enter(
  RiderState state,
  ApiClient api,
  CountingClient client,
  List<void Function()> stops,
) {
  // Signed in, in front: the rider config watch runs in every state
  // (signed_in_loads.dart); the app keeps it while in the background.
  final config = ApiRiderConfigRepository(
    api: api,
    cache: _MemoryConfigCache(),
    homeZoneId: 'zone_budget',
  );
  unawaited(config.watch('zone_budget'));
  stops.add(config.dispose);

  final onHome = switch (state) {
    RiderState.homeIdle ||
    RiderState.quoting ||
    RiderState.homeConfigStreamDown => true,
    _ => false,
  };
  // app_lifecycle.dart: the trip watch runs while the app is in front.
  if (state != RiderState.background) {
    final watch = RiderTripWatch(
      showsHome: () => onHome,
      adopt: () async {
        await ApiActiveTripRepository(api: api).fetchActive();
      },
      // R09 N5: measured with one booked ride (the banner check runs);
      // without one it is not sent.
      hasBooked: () => true,
      bookedOnTheWay: () async {
        await api.get(RiderTripWatch.bookedOnTheWayPath);
        return false;
      },
      refreshBooked: () async {
        // AppScope.reservations.refresh() reads this list.
        await api.get(ApiReservationRepository.listPath);
      },
    )..start();
    stops.add(watch.stop);
  }

  const here = GeoPoint(41.33, 19.82);
  switch (state) {
    case RiderState.homeIdle:
    case RiderState.homeConfigStreamDown:
      // home.dart: presence ping while Home is on screen.
      final presence = HomePresence(
        ping: HomePresence.nearbyCars(api),
        position: () => here,
        signedIn: () async => true,
      )..start();
      stops.add(presence.dispose);
    case RiderState.quoting:
      // select_ride.dart: the cars near the pickup (Home is covered, so
      // presence is stopped). The quote itself is one request on entry.
      final cars = NearbyCarsController(
        source: NearbyCarsController.apiSource(api),
      )..watch(here);
      stops.add(cars.dispose);
    case RiderState.searching:
    case RiderState.driverArriving:
    case RiderState.onTrip:
    case RiderState.tripFinished:
    case RiderState.arrivingTripStreamDown:
      client.tripStatus = switch (state) {
        RiderState.searching => 'searching',
        RiderState.onTrip => 'in_progress',
        RiderState.tripFinished => 'completed',
        _ => 'driver_to_pickup',
      };
      final rt = ApiRideRealtime(api: api);
      final sub = rt.subscribe(tripId).listen((RideRealtimeEvent _) {});
      stops.add(() => unawaited(sub.cancel()));
      // waiting_for_driver.dart: the chat page read once on the trip screen
      // (v0.18.56 §78: the badge then follows the trip stream)
      // (Waiting covers arriving and the trip itself).
      if (state == RiderState.driverArriving ||
          state == RiderState.onTrip ||
          state == RiderState.arrivingTripStreamDown) {
        final messages = MessagesController.forRide(
          tripId,
          transport: ApiTripMessages(api: api),
        );
        unawaited(messages.refresh());
        stops.add(messages.dispose);
      }
    case RiderState.background:
      break;
  }
}
