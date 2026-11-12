import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';

import 'check_log.dart';
import 'rider_steps.dart';

/// UI steps of the rider trip run, on the real trip screens, by the app's
/// keys (waiting_for_driver.dart, waiting_sheet_bits.dart, trip_pin_card,
/// rider_in_trip_panel, chat.dart, call_screen.dart, ride_safety_kit,
/// ride_completed.dart). G31 rider; the pattern of the driver suite's
/// trip_steps.dart.

bool findingShown() => shows(find.byType(FindingDrivers));

bool tripScreenShown() => shows(find.byType(WaitingForDriver));

bool chatOpen() => shows(find.byType(Chat));

bool callOpen() => shows(find.byType(TripCallScreen));

bool safetyKitOpen() => shows(find.byType(RideSafetyKitSheet));

bool completedShown() => shows(find.byType(RideCompleted));

/// True when the trip screen is the top page (no chat, call, sheet).
bool onTripTop() {
  final f = find.byType(WaitingForDriver);
  if (!shows(f)) return false;
  return ModalRoute.of(f.evaluate().first)?.isCurrent ?? false;
}

/// Back until the trip screen is on top again (at most [tries]).
Future<void> backToTrip(WidgetTester tester, {int tries = 3}) async {
  for (var i = 0; i < tries && !onTripTop(); i++) {
    await systemBack(tester);
  }
}

/// The rider screen's trip stage: `waiting-stage-<RideStatus name>` on
/// the trip sheet, else the app's ride session status.
String? riderStage() {
  final keys = keysOf(byKeyPrefix('waiting-stage-'));
  if (keys.isNotEmpty) return keys.first.substring('waiting-stage-'.length);
  return AppScope.instance.ride.status.name;
}

/// The rider UI stage each server status shows as
/// (`RideStatusWire.fromProjection`, core/contracts/trip_status.dart).
const Map<String, Set<String>> stageFor = <String, Set<String>>{
  'accepted': {'driverAssigned', 'driverArriving'},
  'driver_to_pickup': {'driverArriving', 'driverAssigned'},
  'arrived': {'driverWaiting'},
  'rider_onboard': {'tripStarted', 'tripInProgress'},
  'in_trip': {'tripInProgress', 'tripStarted', 'approachingDropoff'},
};

/// The PIN digits the rider sees (`trip-pin-card`: "1 2 3 4"), or null.
String? pinShown() {
  for (final t in textsUnder(byKey('trip-pin-card'))) {
    final digits = t.replaceAll(' ', '');
    if (RegExp(r'^\d{4}$').hasMatch(digits)) return digits;
  }
  return null;
}

/// Makes [target] tappable on the trip sheet: the compact row brings the
/// sheet to the middle, the panel's scroll brings the control into view,
/// and a drag on the sheet's handle opens it further. Says each move.
Future<bool> revealOnSheet(
  WidgetTester tester,
  Finder target, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  bool ready() => tester.any(target.hitTestable());
  final end = DateTime.now().add(timeout);
  var moves = 0;
  while (!ready() && DateTime.now().isBefore(end) && !pastStepsHardStop) {
    if (moves < 6) {
      moves++;
      final compact = byKey('waiting-compact-row').hitTestable();
      if (tester.any(compact)) {
        CheckLog.say('STEP trip sheet: compact row tapped');
        await tester.tap(compact.first, warnIfMissed: false);
        await wait(tester, const Duration(milliseconds: 700));
      } else if (shows(target)) {
        try {
          await tester.ensureVisible(target.first);
          await tester.pump(const Duration(milliseconds: 300));
        } catch (_) {
          // Not in a scrollable.
        }
        if (!ready() && shows(byKey('waiting-panel'))) {
          CheckLog.say('STEP trip sheet: dragged up');
          final top = tester.getRect(byKey('waiting-panel').first).top;
          final x = tester.getCenter(byKey('waiting-panel').first).dx;
          await tester.dragFrom(Offset(x, top + 8), const Offset(0, -320));
          await wait(tester, const Duration(milliseconds: 700));
        }
      }
    }
    if (ready()) break;
    await pumpUntil(tester, ready, timeout: const Duration(seconds: 1));
  }
  return ready();
}

/// Taps the trip sheet's control [key] (revealed first). A miss names the
/// key and whether it was in the tree.
Future<bool> tapOnSheet(
  WidgetTester tester,
  String key, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final target = byKey(key);
  if (!await revealOnSheet(tester, target, timeout: timeout)) {
    CheckLog.miss(
      '"$key" not tappable on the trip sheet in ${timeout.inSeconds} s '
      '(in tree=${shows(target)}, stage=${riderStage()})',
    );
    return false;
  }
  if (!await tapHit(tester, target, '"$key"')) return false;
  await tester.pump(const Duration(milliseconds: 400));
  return true;
}

/// The unread badge on the driver card's Message button (0 when none).
int chatUnread() {
  final texts = textsUnder(byKey('waiting-chat-unread'));
  if (texts.isEmpty) return 0;
  return int.tryParse(texts.first.replaceAll('+', '')) ?? 1;
}

/// The text field of the open chat.
Finder chatField() => find.descendant(
  of: byKey('chat-field'),
  matching: find.byType(EditableText),
);

/// The call screen's state line ("Calling…", "Call ended", …).
String? callStateLine() => textOf('call-state');

/// Opens the safety kit from the trip screen (map button, else the sheet
/// row). Returns whether it opened.
Future<bool> openSafetyKit(WidgetTester tester) async {
  final button = byKey('trip-safety-button');
  if (tester.any(button.hitTestable())) {
    await tester.tap(button.hitTestable().first, warnIfMissed: false);
  } else if (!await tapOnSheet(tester, 'trip-safety-row')) {
    CheckLog.miss(
      'neither "trip-safety-button" nor "trip-safety-row" tappable',
    );
    return false;
  }
  return pumpUntil(tester, safetyKitOpen, timeout: const Duration(seconds: 8));
}

/// Waits until the rider screen shows one of [stages] (or [extra] is
/// true). Returns the seconds it took, or null after [timeout].
Future<int?> waitStage(
  WidgetTester tester,
  Set<String> stages, {
  Duration timeout = const Duration(seconds: 20),
  bool Function()? extra,
}) async {
  final from = DateTime.now();
  final seen = await pumpUntil(
    tester,
    () => stages.contains(riderStage()) || (extra?.call() ?? false),
    timeout: timeout,
  );
  return seen ? DateTime.now().difference(from).inSeconds : null;
}
