import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/shared/widgets/push_permission_primer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Push implements PushService {
  int registers = 0;
  bool deny = false;

  @override
  Future<void> register() async {
    registers += 1;
    if (deny) throw const PushPermissionDeniedException();
  }

  @override
  Future<void> unregister() async {}

  @override
  Stream<PushPayload> get foregroundMessages => const Stream.empty();

  @override
  Stream<PushPayload> get openedMessages => const Stream.empty();

  @override
  Future<PushPayload?> takeInitialMessage() async => null;
}

/// UI-17 / FLOW-19: the OS prompt runs only after the in-app explanation,
/// and a refusal leads to Settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sign-in and session restore never prompt before the explanation',
    () async {
      final push = _Push();
      final gate = PushPermissionGate(push: push, enabled: true);
      await gate.registerIfConsented(logEvent: 'test');
      expect(push.registers, 0);
      expect(await gate.shouldOffer(), isTrue);
      await gate.decline();
      await gate.registerIfConsented(logEvent: 'test');
      expect(push.registers, 0);
      expect(await gate.shouldOffer(), isFalse);
    },
  );

  test('accepting registers now and on later sign-ins', () async {
    final push = _Push();
    final gate = PushPermissionGate(push: push, enabled: true);
    expect(await gate.accept(), PushOptInResult.registered);
    expect(push.registers, 1);
    await gate.registerIfConsented(logEvent: 'test');
    expect(push.registers, 2);
  });

  test('rider-r4-40: a system refusal is remembered, and push registers '
      'again once Settings allows it', () async {
    final push = _Push()..deny = true;
    final gate = PushPermissionGate(push: push, enabled: true);
    expect(await gate.accept(), PushOptInResult.blockedBySystem);
    expect(await gate.consent(), PushConsent.blockedBySystem);
    // The rider turns notifications on in Settings; the next sign-in or
    // cold start registers (the OS answers without a new prompt).
    push.deny = false;
    await gate.registerIfConsented(logEvent: 'test');
    expect(push.registers, 2);
    expect(await gate.consent(), PushConsent.accepted);
  });

  test('signing in never shows the OS prompt before the explanation', () async {
    final push = _Push();
    final gate = PushPermissionGate(push: push, enabled: true);
    AuthController signIn() {
      final tokens = MemoryTokenStore();
      return AuthController(
        auth: AuthRepository(
          api: ApiClient(
            env: const AppEnv(
              flavor: AppFlavor.test,
              apiBaseUrl: 'https://api.test.movera.invalid',
            ),
            client: InProcessMockClient(),
            tokens: tokens,
          ),
          tokens: tokens,
        ),
        pushPermission: gate,
      );
    }

    final first = signIn();
    final challenge = await first.requestOtp(phone: '+46701234567');
    await first.verifyOtp(challenge: challenge, code: '1234');
    expect(push.registers, 0, reason: 'no explanation accepted yet');

    // After "Turn on notifications", the next sign-in registers directly.
    await gate.accept();
    expect(push.registers, 1);
    final second = signIn();
    final again = await second.requestOtp(phone: '+46701234567');
    await second.verifyOtp(challenge: again, code: '1234');
    // rider-u67: registration runs on after sign-in returns.
    await pumpEventQueue();
    expect(push.registers, 2);
  });

  testWidgets('the explanation leads to the OS prompt, then to Settings', (
    tester,
  ) async {
    final push = _Push()..deny = true;
    final gate = PushPermissionGate(push: push, enabled: true);
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => maybeShowPushPrimer(
                context,
                gate: gate,
                openAppSettings: () async {
                  settings += 1;
                  return true;
                },
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Get ride updates'), findsOneWidget);
    expect(push.registers, 0, reason: 'no OS prompt before the tap');
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(push.registers, 1);
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(settings, 1);
  });

  testWidgets('rider-r4-45: swiping the explanation away counts as Not now', (
    tester,
  ) async {
    final push = _Push();
    final gate = PushPermissionGate(push: push, enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => maybeShowPushPrimer(context, gate: gate),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Get ride updates'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();
    expect(find.text('Get ride updates'), findsNothing);
    expect(await gate.shouldOffer(), isFalse);
    expect(push.registers, 0);
  });

  testWidgets('the Notifications screen offers a way back', (tester) async {
    SharedPreferences.setMockInitialValues({
      PushPermissionGate.storageKey: PushConsent.blockedBySystem.name,
    });
    final gate = PushPermissionGate(push: _Push(), enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PushStatusBanner(gate: gate)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ride updates are off'), findsOneWidget);
    await tester.tap(find.text('Ride updates are off'));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('rider-95: on the web the way back is the browser, not an '
      'Open settings button that throws', (tester) async {
    SharedPreferences.setMockInitialValues({
      PushPermissionGate.storageKey: PushConsent.blockedBySystem.name,
    });
    final push = _Push();
    final gate = PushPermissionGate(push: push, enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PushStatusBanner(gate: gate, isWeb: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn them on in your browser settings.'), findsOneWidget);
    await tester.tap(find.text('Ride updates are off'));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsNothing);
    expect(find.textContaining('this site in your browser'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(push.registers, 1);
  });

  testWidgets('mock push offers nothing', (tester) async {
    final gate = PushPermissionGate(push: _Push(), enabled: false);
    expect(await gate.shouldOffer(), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PushStatusBanner(gate: gate)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ride updates are off'), findsNothing);
  });
}
