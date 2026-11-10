import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';

import 'request_budget_harness.dart';

/// Global plan step 62 (T3): the request budget per state of the rider app.
/// A state that sends more than its budget (+ [margin]) fails here. A PR
/// that raises a number changes [budgets] AND docs/request-budgets.md and
/// says why (GLOBAL-SAFE-PLAN T3).
const Map<RiderState, Map<String, double>> budgets = {
  RiderState.homeIdle: {
    'GET /api/v1/rider/trips/active': 7.5,
    'GET /api/v1/rider/nearby-vehicles': 1.4,
  },
  RiderState.quoting: {
    'GET /api/v1/rider/trips/active': 7.5,
    'GET /api/v1/rider/nearby-vehicles': 12.0,
  },
  RiderState.searching: {
    'GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived':
        7.5,
  },
  RiderState.driverArriving: {
    'GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived':
        7.5,
    'GET /api/v1/trips/{tripId}/messages': 6.0,
  },
  RiderState.onTrip: {
    'GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived':
        7.5,
    'GET /api/v1/trips/{tripId}/messages': 6.0,
  },
  RiderState.tripFinished: {
    'GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived':
        7.5,
  },
  RiderState.background: {},
  RiderState.homeConfigStreamDown: {
    'GET /api/v1/rider/config': 1.1,
    'GET /api/v1/rider/config/stream (SSE open)': 1.1,
    'GET /api/v1/rider/trips/active': 7.5,
    'GET /api/v1/rider/nearby-vehicles': 1.4,
  },
  RiderState.arrivingTripStreamDown: {
    'GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived':
        7.5,
    'GET /api/v1/trips/{tripId}/messages': 6.0,
    'GET /api/v1/trips/{tripId}': 6.0,
    'GET /api/v1/trips/{tripId}/events (SSE open)': 1.1,
  },
};

/// Allowed over a budget: 10 % or 0.5 a minute, whichever is larger.
double margin(double budget) => budget * 0.1 > 0.5 ? budget * 0.1 : 0.5;

/// Every endpoint over its budget (an endpoint with no budget has 0).
List<String> overBudget(StateMeasure m) {
  final allowed = budgets[m.state]!;
  return [
    for (final e in m.perMinute.entries)
      if (e.value > (allowed[e.key] ?? 0) + margin(allowed[e.key] ?? 0))
        '${m.state.name}: ${e.key} ${e.value.toStringAsFixed(2)}/min '
            '> budget ${allowed[e.key] ?? 0}',
  ];
}

void main() {
  final measured = {for (final s in RiderState.values) s: measure(s)};

  test('prints the measured table (docs/request-budgets.md)', () {
    final out = StringBuffer();
    for (final m in measured.values) {
      final keys = {...m.perMinute.keys, ...m.onEntry.keys}.toList()..sort();
      for (final k in keys) {
        out.writeln(
          '| ${m.state.name} | `$k` | ${m.onEntry[k] ?? 0} | '
          '${(m.perMinute[k] ?? 0).toStringAsFixed(2)} |',
        );
      }
    }
    // ignore: avoid_print
    print(out);
  });

  for (final state in RiderState.values) {
    test('${state.name} stays inside its request budget', () {
      expect(overBudget(measured[state]!), isEmpty);
    });
  }

  test('every budget is written in docs/request-budgets.md', () {
    final doc = File('docs/request-budgets.md').readAsStringSync();
    for (final entry in budgets.entries) {
      for (final b in entry.value.entries) {
        expect(
          doc.contains('| ${entry.key.name} | `${b.key}` | ${b.value} |'),
          isTrue,
          reason: '${entry.key.name} ${b.key} ${b.value} missing in the doc',
        );
      }
    }
  });

  test('the check fails on one extra poll (Rule 35 guard)', () {
    // An extra 30 s read of the active trip on Home: +2 a minute.
    final m = measure(
      RiderState.homeIdle,
      extra: (ApiClient api, stops) {
        final t = Timer.periodic(
          const Duration(seconds: 30),
          (_) => unawaited(ApiActiveTripRepository(api: api).fetchActive()),
        );
        stops.add(t.cancel);
      },
    );
    expect(overBudget(m), isNotEmpty);
  });
}
