import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';

import 'contract_fixtures.dart';

/// Contract v0.3.1 lifecycle: the Dart enums and the transition engine are
/// checked against the shipped `contracts/contract.json` and replay
/// `fixtures/scenarios.json` with the reference engine's answers.
void main() {
  final trip = contract['tripStatus'] as Map<String, dynamic>;

  group('TripStatus vocabulary', () {
    test('values and terminal set equal contract.json', () {
      expect(
        TripStatus.values.map((s) => s.wireName).toList(),
        List<String>.from(trip['values'] as List),
      );
      expect(
        tripTerminalStatuses.map((s) => s.wireName).toSet(),
        Set<String>.from(trip['terminal'] as List),
      );
      expect(
        tripDriverAssignedStatuses.map((s) => s.wireName).toSet(),
        Set<String>.from(trip['driverAssigned'] as List),
      );
      expect(
        tripRiderOnboardStatuses.map((s) => s.wireName).toSet(),
        Set<String>.from(trip['riderOnboard'] as List),
      );
      for (final status in TripStatus.values) {
        expect(TripStatusWire.parse(status.wireName), status);
        expect(status.isTerminal, tripTerminalStatuses.contains(status));
      }
    });

    test('payment and rating vocabularies equal contract.json', () {
      expect(
        TripPaymentStatus.values.map((s) => s.wireName).toList(),
        List<String>.from(contract['paymentStatus'] as List),
      );
      expect(
        TripRatingStatus.values.map((s) => s.wireName).toList(),
        List<String>.from(contract['ratingStatus'] as List),
      );
      final payment = {
        for (final row in contract['paymentTransitions'] as List)
          '${row['from']}>${row['to']}',
      };
      expect({
        for (final entry in tripPaymentTransitions.entries)
          for (final to in entry.value) '${entry.key.wireName}>${to.wireName}',
      }, payment);
      final rating = {
        for (final row in contract['ratingTransitions'] as List)
          '${row['from']}>${row['to']}',
      };
      expect({
        for (final entry in tripRatingTransitions.entries)
          for (final to in entry.value) '${entry.key.wireName}>${to.wireName}',
      }, rating);
    });
  });

  group('transition engine', () {
    test('table equals contract.json#transitions row by row', () {
      final rows = [
        for (final row in contract['transitions'] as List)
          (
            row['command'] as String,
            row['actor'] as String,
            (List<String>.from(row['from'] as List)..sort()).join(','),
            row['to'] as String,
            row['when'] as String?,
          ),
      ];
      final ours = [
        for (final t in TripStateMachine.transitions)
          (
            t.command,
            t.actor.wireName,
            (t.from.map((s) => s.wireName).toList()..sort()).join(','),
            t.to.wireName,
            t.when?.wireName,
          ),
      ];
      expect(ours, rows);
    });

    test('replays fixtures/scenarios.json identically', () {
      final fixture = contractJson('fixtures/scenarios.json')!
          as Map<String, dynamic>;
      final scenarios = fixture['scenarios'] as List;
      expect(scenarios, isNotEmpty);
      for (final scenario in scenarios) {
        final kind = TripKindWire.parse(scenario['kind'])!;
        var status = TripStatus.draft;
        for (final step in scenario['steps'] as List) {
          final [command, actor, expected] = List<String>.from(step as List);
          final next = TripStateMachine.apply(
            status,
            command,
            TripActorWire.parse(actor)!,
            kind: kind,
          );
          expect(
            next?.wireName ?? 'invalid_transition',
            expected,
            reason: '${scenario['id']}: $command by $actor from '
                '${status.wireName}',
          );
          if (next != null) status = next;
        }
      }
    });

    test('rating rules equal contract.json#ratingAllowed row by row', () {
      final rows = [
        for (final row in (contract['ratingAllowed'] as Map)['rules'] as List)
          (row['rater'] as String, row['status'] as String,
            row['command'] as String?),
      ];
      final ours = [
        for (final rule in TripRatingRules.rules)
          (rule.rater.wireName, rule.status.wireName, rule.command),
      ];
      expect(ours, rows);
    });

    test('replays the rating cases of fixtures/scenarios.json', () {
      final fixture = contractJson('fixtures/scenarios.json')!
          as Map<String, dynamic>;
      final cases = [
        for (final scenario in fixture['scenarios'] as List)
          if ((scenario as Map)['rating'] != null) scenario,
      ];
      expect(
        cases.map((s) => s['id']),
        containsAll([
          'rider_rates_trip_ended_early',
          'plain_rider_cancel_is_not_rated',
        ]),
      );
      for (final scenario in cases) {
        final kind = TripKindWire.parse(scenario['kind'])!;
        var status = TripStatus.draft;
        String? endedBy;
        for (final step in scenario['steps'] as List) {
          final [command, actor, _] = List<String>.from(step as List);
          final next = TripStateMachine.apply(
            status,
            command,
            TripActorWire.parse(actor)!,
            kind: kind,
          );
          if (next != null) (status, endedBy) = (next, command);
        }
        for (final MapEntry(key: rater, value: expected)
            in (scenario['rating'] as Map).entries) {
          final allowed = status.isTerminal &&
              TripRatingRules.allows(
                TripActorWire.parse(rater)!,
                status,
                endedBy: endedBy,
              );
          expect(
            allowed ? 'allowed' : 'invalid_transition',
            expected,
            reason: '${scenario['id']}: $rater rates after '
                '${status.wireName} by $endedBy',
          );
        }
      }
    });

    test('terminal statuses have no way out', () {
      for (final status in tripTerminalStatuses) {
        for (final t in TripStateMachine.transitions) {
          expect(t.from.contains(status), isFalse, reason: t.command);
        }
      }
    });
  });

  group('Rider UI states derived from the projection', () {
    test('each terminal cause has its own UI state', () {
      final terminals = {
        for (final status in tripTerminalStatuses)
          if (status != TripStatus.completed) RideStatusWire.fromTrip(status),
      };
      expect(terminals, hasLength(tripTerminalStatuses.length - 1));
      expect(
        RideStatusWire.parse('cancelled_by_system'),
        RideStatus.cancelledBySystem,
      );
      expect(
        RideStatusWire.parse('cancelled_by_admin'),
        RideStatus.cancelledByAdmin,
      );
      expect(RideStatusWire.parse('no_show'), RideStatus.noShow);
      expect(RideStatusWire.parse('failed'), RideStatus.tripFailed);
      expect(RideStatusWire.parse('cancelled_by_driver'), RideStatus.endedByDriver);
      for (final status in terminals) {
        expect(status.isTerminal, isTrue, reason: status.name);
        // And back to the same trip status: the round trip is lossless.
        expect(RideStatusWire.fromTrip(status.tripStatus), status);
      }
    });

    test('payment and rating are fields on a completed trip', () {
      RideStatus? ui(Map<String, Object?> projection) =>
          RideStatusWire.fromProjection(projection);
      expect(ui({'status': 'completed'}), RideStatus.tripCompleted);
      expect(
        ui({'status': 'completed', 'paymentStatus': 'authorized'}),
        RideStatus.paymentProcessing,
      );
      expect(
        ui({'status': 'completed', 'paymentStatus': 'failed'}),
        RideStatus.paymentFailed,
      );
      expect(
        ui({
          'status': 'completed',
          'paymentStatus': 'captured',
          'ratingStatus': 'not_requested',
        }),
        RideStatus.paymentFinalized,
      );
      expect(
        ui({
          'status': 'completed',
          'paymentStatus': 'captured',
          'ratingStatus': 'pending',
        }),
        RideStatus.ratingPending,
      );
      for (final post in [
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
        RideStatus.paymentFailed,
        RideStatus.closed,
      ]) {
        expect(post.tripStatus, TripStatus.completed, reason: post.name);
      }
    });

    test('`expired` parses one way everywhere', () {
      expect(RideStatusWire.parse('expired'), RideStatus.noDriverFound);
    });
  });

  test('rider cancel reason registry equals contract.json rider codes', () {
    final reasons = contract['cancelReasons'] as Map<String, dynamic>;
    expect(CancelReasonCodes.rider, List<String>.from(reasons['rider'] as List));
    expect(CancelReasonCodes.admin, List<String>.from(reasons['admin'] as List));
    expect(
      CancelReasonCodes.system,
      List<String>.from(reasons['system'] as List),
    );
    expect(
      CancelReasonCodes.noShow,
      List<String>.from(reasons['noShow'] as List),
    );
    for (final phase in CancelPhase.values) {
      for (final reason in CancellationReason.forPhase(phase)) {
        expect(CancelReasonCodes.isRiderCode(reason.id), isTrue, reason: reason.id);
      }
    }
  });

  test('category seed and alias equal contract.json', () {
    final categories = contract['categories'] as Map<String, dynamic>;
    expect(CategoryIds.seed, List<String>.from(categories['seed'] as List));
    expect(
      CategoryIds.aliases,
      Map<String, String>.from(categories['aliases'] as Map),
    );
    expect(CategoryIds.canonical('movera'), 'economy');
    expect(CategoryIds.canonical('comfort'), 'comfort');
    expect(CategoryIds.pattern.pattern, categories['pattern']);
  });
}
