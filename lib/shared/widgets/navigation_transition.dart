import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';

class BottomToTopTransition<T> extends PageRouteBuilder<T> {
  BottomToTopTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: MoveraDurations.large,
          reverseTransitionDuration: MoveraDurations.normal,
          transitionsBuilder: (context, animation, secondary, child) {
            return _sheetCover(context, animation, child);
          },
        );
}

class TopToBottomTransition<T> extends PageRouteBuilder<T> {
  TopToBottomTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: MoveraDurations.large,
          reverseTransitionDuration: MoveraDurations.normal,
          transitionsBuilder: (context, animation, secondary, child) {
            if (MoveraMotion.reduced(context)) return child;
            return _Curved(
              animation: animation,
              curve: MoveraCurves.open,
              reverseCurve: MoveraCurves.close,
              builder: (curved) => FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.06),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Full-screen ride lifecycle stages use a deliberately quiet transition.
///
/// Map-heavy ride pages must not slide over one another for hundreds of
/// milliseconds: on web/PWA that briefly keeps two platform maps alive and can
/// look like a crash. Forward navigation gets a short fade; unwinding the ride
/// stack back to Home is instantaneous so intermediate stages never flash.
class RideStageTransition<T> extends PageRouteBuilder<T> {
  RideStageTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: const Duration(milliseconds: 120),
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondary, child) {
            if (MoveraMotion.reduced(context)) return child;
            // Never fade the incoming ride stage itself. Fading the whole
            // child exposes the previous stage underneath for a few frames,
            // which is especially visible after that stage has already parked
            // its map. Keep an opaque neutral surface behind the new stage and
            // fade only a very light veil over the new screen.
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFFF6F5F1)),
                child,
                IgnorePointer(
                  child: _Curved(
                    animation: animation,
                    curve: Curves.easeOutCubic,
                    builder: (curved) => FadeTransition(
                      opacity: Tween<double>(begin: 0.12, end: 0).animate(curved),
                      child: const ColoredBox(color: Color(0xFFF6F5F1)),
                    ),
                  ),
                ),
              ],
            );
          },
        );
}

class SwitchTransition<T> extends PageRouteBuilder<T> {
  SwitchTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: MoveraDurations.normal,
          reverseTransitionDuration: MoveraDurations.micro,
          transitionsBuilder: (context, animation, secondary, child) {
            if (MoveraMotion.reduced(context)) return child;
            return _Curved(
              animation: animation,
              curve: MoveraCurves.open,
              reverseCurve: MoveraCurves.close,
              builder: (curved) => FadeTransition(opacity: curved, child: child),
            );
          },
        );
}

class LeftToRightTransition<T> extends PageRouteBuilder<T> {
  LeftToRightTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: MoveraDurations.normal,
          reverseTransitionDuration: MoveraDurations.micro,
          transitionsBuilder: (context, animation, secondary, child) {
            return _sideCover(context, animation, child, const Offset(-0.06, 0));
          },
        );
}

/// The forward page push for non-ride pages (menu, account, wallet, help).
///
/// NAV-13: on native iOS it uses the Cupertino page transition, which carries
/// the interactive edge swipe-back. A page that must not be left that way
/// opts out with a PopScope(canPop: false), which disables the gesture. The
/// web build keeps the Movera transition; there the browser's own edge swipe
/// is history back.
class RightToLeftTransition<T> extends PageRouteBuilder<T> {
  RightToLeftTransition(Widget page, {super.settings})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionDuration: MoveraDurations.normal,
          reverseTransitionDuration: MoveraDurations.micro,
          transitionsBuilder: (context, animation, secondary, child) {
            return _sideCover(context, animation, child, const Offset(0.06, 0));
          },
        );

  bool _iosBackSwipe(BuildContext context) =>
      !kIsWeb && Theme.of(context).platform == TargetPlatform.iOS;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_iosBackSwipe(context)) {
      return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

Widget _sheetCover(BuildContext context, Animation<double> animation, Widget child) {
  if (MoveraMotion.reduced(context)) return child;
  return _Curved(
    animation: animation,
    curve: MoveraCurves.open,
    reverseCurve: MoveraCurves.close,
    builder: (curved) => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
  );
}

Widget _sideCover(
  BuildContext context,
  Animation<double> animation,
  Widget child,
  Offset begin,
) {
  if (MoveraMotion.reduced(context)) return child;
  return _Curved(
    animation: animation,
    curve: MoveraCurves.open,
    reverseCurve: MoveraCurves.close,
    builder: (curved) => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    ),
  );
}

/// rider-j8-14: one [CurvedAnimation] per transition, owned and disposed
/// here. A transitions builder runs on every frame of the route's own
/// animation and of every route above it; a CurvedAnimation made there
/// added a status listener to the route's controller each frame that was
/// never removed, and lost its curve direction on a mid-push pop.
class _Curved extends StatefulWidget {
  const _Curved({
    required this.animation,
    required this.curve,
    this.reverseCurve,
    required this.builder,
  });

  final Animation<double> animation;
  final Curve curve;
  final Curve? reverseCurve;
  final Widget Function(Animation<double> curved) builder;

  @override
  State<_Curved> createState() => _CurvedState();
}

class _CurvedState extends State<_Curved> {
  late CurvedAnimation _curved = _make();

  CurvedAnimation _make() => CurvedAnimation(
    parent: widget.animation,
    curve: widget.curve,
    reverseCurve: widget.reverseCurve,
  );

  @override
  void didUpdateWidget(_Curved old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation ||
        old.curve != widget.curve ||
        old.reverseCurve != widget.reverseCurve) {
      _curved.dispose();
      _curved = _make();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_curved);
}


/// Closes the current modal/page route and waits until its exit transition has
/// fully finished before another route is pushed.
///
/// [Navigator.pop] completes the route's `popped` future immediately, while
/// animated routes can remain in the overlay for several frames. Waiting for
/// [TransitionRoute.completed] prevents close->open handoffs from overlapping
/// or hitting Navigator's transition lock.
Future<void> popCurrentRouteAndWaitForExit(BuildContext context) async {
  final navigator = Navigator.of(context);
  final route = ModalRoute.of(context);
  if (!navigator.canPop()) return;
  navigator.pop();
  if (route != null) {
    await route.completed;
  } else {
    await WidgetsBinding.instance.endOfFrame;
  }
}


/// Wait until the current route's forward transition has fully settled.
///
/// This replaces guessed millisecond delays before mounting platform views
/// such as Google Maps. If the route is already settled, this waits one frame.
Future<void> waitForCurrentRouteToSettle(BuildContext context) async {
  final route = ModalRoute.of(context);
  final animation = route?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    await WidgetsBinding.instance.endOfFrame;
    return;
  }

  final completer = Completer<void>();
  void listener(AnimationStatus status) {
    if (status != AnimationStatus.completed || completer.isCompleted) return;
    animation.removeStatusListener(listener);
    completer.complete();
  }

  animation.addStatusListener(listener);
  if (animation.status == AnimationStatus.completed && !completer.isCompleted) {
    animation.removeStatusListener(listener);
    completer.complete();
  }
  await completer.future;
  await WidgetsBinding.instance.endOfFrame;
}

/// Pushes [route] unless [context]'s route is already no longer the
/// topmost one — i.e. a previous tap already pushed something. Unlike a
/// per-widget in-flight flag, this needs no State: [ModalRoute.isCurrent]
/// flips to false synchronously the instant a route is pushed, before the
/// transition animation even starts, so a rapid double-tap on a
/// StatelessWidget's onTap (which has nowhere to store a boolean) is still
/// caught. Use the per-widget flag pattern instead when the guarded action
/// is async before the push happens (see e.g. SafetyHub._open).
Future<T?> guardedPush<T>(BuildContext context, Route<T> route) {
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
    return Future<T?>.value();
  }
  return Navigator.push<T>(context, route);
}
