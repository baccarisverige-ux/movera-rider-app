import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/home/presentation/home.dart';

import 'check_log.dart';

/// UI steps of the rider device run, on the real app, through its keys
/// (G31 rider; the pattern of the driver suite's driver_steps.dart, merged
/// in Movera-driver-app #570).
///
/// The binding waits in real time: `pump(d)` lets `d` pass on the phone,
/// with real network calls going on meanwhile.

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

bool shows(Finder finder) => finder.evaluate().isNotEmpty;

/// Widgets whose String key starts with [prefix] (e.g. `search-step-`).
Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

/// The String keys of [finder]'s widgets.
List<String> keysOf(Finder finder) => <String>[
  for (final e in finder.evaluate())
    if (e.widget.key case final ValueKey<String> k) k.value,
];

/// Called after every pump of [pumpUntil] (the trip test samples the
/// screen there: blank frames, full-screen loaders). Null = nothing.
void Function()? pumpProbe;

/// Hard stop for the test's steps (the trip test sets it, then clears it
/// for its clean-up): past it every [pumpUntil] / [wait] returns at once,
/// so the running step ends in seconds and the clean-up still runs inside
/// the test's and Test Lab's time limits. Null = none.
DateTime? stepsHardStop;

bool get pastStepsHardStop {
  final stop = stepsHardStop;
  return stop != null && DateTime.now().isAfter(stop);
}

/// Pumps until [done] or [timeout] (or [stepsHardStop]); answers known
/// one-off prompts meanwhile.
///
/// Run 6 lesson (driver suite): never call this while the fake app
/// lifecycle is hidden/paused (frames are off, a live pump never returns).
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 250),
  bool dismiss = true,
}) async {
  var end = DateTime.now().add(timeout);
  final stop = stepsHardStop;
  if (stop != null && stop.isBefore(end)) end = stop;
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    pumpProbe?.call();
    if (done()) return true;
    if (dismiss) await dismissPrompts(tester);
  }
  return done();
}

/// Lets [duration] pass on the phone, answering one-off prompts.
Future<void> wait(WidgetTester tester, Duration duration) =>
    pumpUntil(tester, () => false, timeout: duration);

/// Prompts a fresh install may show over Home. The test answers them the
/// way a rider would to get on with the ride (not now / close / accept the
/// staging terms), and says so in the log. `location-access-action` is
/// never tapped (it opens the phone's settings): Test Lab grants the
/// location permission to an instrumentation run.
const List<String> _prompts = <String>[
  'push-primer-not-now',
  'content-update-close',
  'content-terms-accept',
  'legal-accept-button',
];

Future<void> dismissPrompts(WidgetTester tester) async {
  for (final key in _prompts) {
    final finder = byKey(key).hitTestable();
    if (!tester.any(finder)) continue;
    CheckLog.say('STEP prompt "$key" answered');
    await tester.tap(finder.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Taps [finder] only where a tap really lands on it (hit-testable, not
/// offstage or covered). A tap that would miss is logged as a miss (named
/// [what]) instead of being sent blind. Returns whether it tapped.
Future<bool> tapHit(WidgetTester tester, Finder finder, String what) async {
  final hit = finder.hitTestable();
  if (!tester.any(hit)) {
    CheckLog.miss(
      shows(finder)
          ? '$what is in the tree but not tappable (offstage or covered)'
          : '$what not in the tree',
    );
    return false;
  }
  await tester.tap(hit.first, warnIfMissed: false);
  return true;
}

/// Waits until [key] is tappable (scrolling it into view when it is in
/// the tree), then taps it. A miss names the key.
Future<bool> tapKey(
  WidgetTester tester,
  String key, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final target = byKey(key);
  final ready = await pumpUntil(tester, () {
    return tester.any(target.hitTestable());
  }, timeout: timeout);
  if (!ready && shows(target)) {
    try {
      await tester.ensureVisible(target.first);
      await tester.pump(const Duration(milliseconds: 300));
    } catch (_) {
      // Not in a scrollable.
    }
  }
  if (!tester.any(target.hitTestable())) {
    CheckLog.miss(
      '"$key" not tappable in ${timeout.inSeconds} s (in tree=${shows(target)})',
    );
    return false;
  }
  await tester.tap(target.hitTestable().first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 400));
  return true;
}

/// The error line the sign-in screens show, if any (the app's words; they
/// never repeat the number).
String? authError() {
  final errors = find.byType(AuthErrorText);
  if (!shows(errors)) return null;
  return (errors.evaluate().first.widget as AuthErrorText).message;
}

bool onHome() => shows(find.byType(Home));

/// Signs in with [phone] and [code] through the real screens.
///
/// Returns null on Home, else why not. Already signed in: straight to Home.
/// Never takes a screenshot (both screens show the number).
Future<String?> signIn(
  WidgetTester tester, {
  required String phone,
  required String code,
}) async {
  final first = await pumpUntil(
    tester,
    () => shows(find.byType(SignIn)) || onHome(),
    timeout: const Duration(seconds: 60),
    dismiss: false,
  );
  if (!first) return 'neither the sign-in screen nor Home showed in 60 s';
  if (onHome()) return null;

  final field = find.descendant(
    of: byKey('auth-phone-field'),
    matching: find.byType(EditableText),
  );
  if (!shows(field)) {
    CheckLog.miss('"auth-phone-field" (its text field) not on Sign in');
    return 'sign-in screen has no phone field';
  }
  await tester.enterText(field.first, phone);
  await tester.pump(const Duration(milliseconds: 400));
  if (!await tapHit(tester, byKey('auth-consent'), '"auth-consent"')) {
    return 'consent box not tappable';
  }
  await tester.pump(const Duration(milliseconds: 400));
  final next = byKey('auth-continue');
  if (shows(next)) await tester.ensureVisible(next.first);
  if (!await tapHit(tester, next, '"auth-continue"')) {
    return 'Continue not tappable';
  }
  // A sleeping staging server answers in up to ~60 s.
  final codeScreen = await pumpUntil(
    tester,
    () => shows(find.byType(PhoneVerification)) || authError() != null,
    timeout: const Duration(seconds: 90),
    dismiss: false,
  );
  if (!codeScreen || !shows(find.byType(PhoneVerification))) {
    return 'no code screen after Continue: ${authError() ?? 'timeout 90 s'}';
  }
  final pin = find.descendant(
    of: byKey('auth-code'),
    matching: find.byType(EditableText),
  );
  if (!shows(pin)) {
    CheckLog.miss('"auth-code" (its text field) not on the code screen');
    return 'code screen has no code field';
  }
  await tester.enterText(pin.first, code);
  await tester.pump(const Duration(milliseconds: 600));
  // The last digit sends the code by itself; Verify is the fallback.
  final verify = byKey('auth-verify');
  await tester.pump(const Duration(seconds: 2));
  if (shows(find.byType(PhoneVerification)) &&
      authError() == null &&
      tester.any(verify.hitTestable())) {
    final button = tester.widget(verify);
    if (button is AuthPrimaryButton && button.onPressed != null) {
      await tester.tap(verify.hitTestable().first, warnIfMissed: false);
    }
  }
  final home = await pumpUntil(
    tester,
    () =>
        onHome() ||
        (shows(find.byType(PhoneVerification)) && authError() != null),
    timeout: const Duration(seconds: 90),
  );
  if (!home || !onHome()) {
    return 'code not taken: ${authError() ?? 'Home did not open in 90 s '
            '(a new rider gets the name screen: not a test rider)'}';
  }
  return null;
}

/// Android Back, as the system button sends it.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The app's root navigator (moveraNavigatorKey), or null.
NavigatorState? get rootNavigator => moveraNavigatorKey.currentState;

/// True when Home shows and nothing is pushed above it.
bool onHomeOnly() {
  if (!onHome()) return false;
  final nav = rootNavigator;
  return nav != null && !nav.canPop();
}

/// Back until Home is alone again (at most [tries] presses).
Future<int> backToHome(WidgetTester tester, {int tries = 4}) async {
  var presses = 0;
  while (presses < tries && !onHomeOnly()) {
    await systemBack(tester);
    presses++;
  }
  return presses;
}

/// All texts under [scope] (for amount and field checks; never logged
/// whole: callers log only what they compare).
List<String> textsUnder(Finder scope) => <String>[
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate())
    if ((e.widget as Text).data case final t?)
      t
    else if ((e.widget as Text).textSpan case final s?)
      s.toPlainText(),
];

/// The text of the first Text widget keyed [key], or null.
String? textOf(String key) {
  final f = byKey(key);
  if (!shows(f)) return null;
  final w = f.evaluate().first.widget;
  if (w is Text) return w.data ?? w.textSpan?.toPlainText();
  final inner = textsUnder(f.first);
  return inner.isEmpty ? null : inner.join(' ');
}
