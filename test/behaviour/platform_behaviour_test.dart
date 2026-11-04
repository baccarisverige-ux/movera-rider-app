import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/secure_token_store.dart';
import 'package:movera_rider/shared/design_system/motion/movera_durations.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B16 (2026-11-04): behaviour tests that replace source-reading guards
/// (archived in Rules/archive/old-tests/movera-rider-app/).
void main() {
  group('tokens never land in SharedPreferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
    ]) {
      testWidgets('on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final store = SecureTokenStore();
        await store.save(access: 'acc-b16-secret', refresh: 'ref-b16-secret');
        expect(await store.readAccess(), 'acc-b16-secret');
        expect(await store.readRefresh(), 'ref-b16-secret');

        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        for (final key in prefs.getKeys()) {
          final value = '${prefs.get(key)}';
          expect(value, isNot(contains('acc-b16-secret')), reason: key);
          expect(value, isNot(contains('ref-b16-secret')), reason: key);
        }
        if (platform != TargetPlatform.linux) {
          // Phones keep them in the Keychain / Keystore.
          final secure = await const FlutterSecureStorage().readAll();
          expect(secure.values.join(), contains('acc-b16-secret'));
        }
        await store.clear();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('page transitions use the shared motion tokens', () {
    final allowed = {
      MoveraDurations.micro,
      MoveraDurations.normal,
      MoveraDurations.large,
      MoveraDurations.sheetOpen,
      MoveraDurations.sheetClose,
    };
    final routes = <String, PageRouteBuilder<void> Function(Widget)>{
      'BottomToTop': (p) => BottomToTopTransition<void>(p),
      'TopToBottom': (p) => TopToBottomTransition<void>(p),
      'Switch': (p) => SwitchTransition<void>(p),
      'LeftToRight': (p) => LeftToRightTransition<void>(p),
      'RightToLeft': (p) => RightToLeftTransition<void>(p),
    };

    routes.forEach((name, make) {
      testWidgets('$name animates with a token duration', (tester) async {
        final route = make(const SizedBox());
        expect(allowed, contains(route.transitionDuration), reason: name);
        expect(
          allowed,
          contains(route.reverseTransitionDuration),
          reason: name,
        );
        expect(route.transitionDuration, lessThan(const Duration(seconds: 1)));

        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, home: const Text('below')),
        );
        nav.currentState!.push(make(const Text('page-b16')));
        await tester.pump();
        await tester.pump(route.transitionDuration ~/ 3);
        // Mid-way the page is still moving: it is wrapped in a transition,
        // not handed back bare.
        final moving = find.ancestor(
          of: find.text('page-b16'),
          matching: find.byWidgetPredicate(
            (w) =>
                w is FadeTransition ||
                w is SlideTransition ||
                w is ScaleTransition ||
                w is AnimatedBuilder,
          ),
        );
        expect(moving, findsWidgets, reason: name);
        await tester.pumpAndSettle();
        expect(find.text('page-b16'), findsOneWidget);
      });
    });

    testWidgets('ride stages fade in quickly and leave instantly', (
      tester,
    ) async {
      final route = RideStageTransition<void>(const SizedBox());
      expect(
        route.transitionDuration,
        lessThanOrEqualTo(MoveraDurations.micro),
      );
      expect(route.reverseTransitionDuration, Duration.zero);
    });
  });
}
