import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/search_step.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Fix job N2 + P17 + far rider (contract v0.18.39 §63,
/// contract.json#noDriverNearby). Rider app: the "No driver nearby" step with
/// Keep waiting / Cancel free (owner N2), and a booked ride with no driver
/// told "No driver found" when the server ends it at pickup + 15 min (P17).
/// Rule 36: written before the fix; on main the step kind is dropped
/// (search_step.dart kinds), Stop says "Stop searching" and the client gave
/// up at pickup + 5 min.
void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync())
          as Map<String, dynamic>;
  final nd = contract['noDriverNearby'] as Map<String, dynamic>;

  test('no_driver_nearby is read and asks Keep waiting / Cancel free', () {
    final step = TripSearchStep.fromWire({
      'id': 'nd',
      'kind': 'no_driver_nearby',
      'message': 'No driver nearby right now. We keep searching for you.',
      'extraMin': null,
      'at': '2026-11-06T10:05:00Z',
    });
    expect(step, isNotNull);
    expect(step!.asksKeepWaiting, isTrue);
    expect(step.message, isNotEmpty);
  });

  test('no_driver_found (P17) is read and asks nothing', () {
    final step = TripSearchStep.fromWire({
      'id': 'nf',
      'kind': 'no_driver_found',
      'message': 'No driver was found for your booked ride. You pay nothing.',
    });
    expect(step, isNotNull);
    expect(step!.asksKeepWaiting, isFalse);
  });

  test('the texts are the contract words in sv, fr and en', () {
    final texts = nd['texts'] as Map<String, dynamic>;
    for (final lang in ['sv', 'fr', 'en']) {
      final l10n = lookupAppLocalizations(Locale(lang));
      expect(
        l10n.searchStepNoDriverNearby,
        (texts['no_driver_nearby'] as Map)[lang],
        reason: lang,
      );
      expect(
        l10n.searchStepNoDriverFound,
        (texts['no_driver_found'] as Map)[lang],
        reason: lang,
      );
      expect(
        l10n.searchStepStop,
        (texts['cancelFree'] as Map)[lang],
        reason: lang,
      );
      expect(
        l10n.keepWaiting,
        (texts['keepWaiting'] as Map)[lang],
        reason: lang,
      );
    }
  });

  test('a booked ride with no driver is "No driver found" at pickup + 15 '
      'min, the server stop time (P17), not before', () {
    final defaults = nd['defaults'] as Map<String, dynamic>;
    expect(
      ReservationController.noDriverFoundAfter,
      Duration(minutes: defaults['noDriverStopAfterMin'] as int),
    );
  });
}
