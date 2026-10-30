import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:pinput/pinput.dart';

/// Counts the verify calls that reach the stand-in server.
class _Counting extends http.BaseClient {
  _Counting(this.inner);

  final InProcessMockClient inner;
  final List<String> verifyCodes = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/auth/otp/verify') &&
        request is http.Request) {
      final match = RegExp(r'"code":"(\d+)"').firstMatch(request.body);
      verifyCodes.add(match?.group(1) ?? '?');
    }
    return inner.send(request);
  }
}

/// Contract v0.18.2 (owner 2026-10-30): `auth.codeAutoSubmit` "Check by
/// itself (Recommended)" and `auth.codeClearOnWrong` "Clear boxes
/// (Recommended)".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => PhoneVerification.debugWeb = null);

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );
  const latency = Duration(milliseconds: 500);

  late _Counting client;

  Finder codeField() => find.descendant(
    of: find.byType(Pinput),
    matching: find.byType(EditableText),
  );

  Future<void> openCodeScreen(WidgetTester tester) async {
    final tokens = MemoryTokenStore();
    client = _Counting(InProcessMockClient(latency: latency));
    final auth = AuthController(
      auth: AuthRepository(
        api: ApiClient(env: env, client: client, tokens: tokens),
        tokens: tokens,
      ),
    );
    final challenge = (await tester.runAsync(
      () => auth.requestOtp(phone: '+46701234567'),
    ))!;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: PhoneVerification(challenge: challenge, controller: auth),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  String typed(WidgetTester tester) =>
      tester.widget<Pinput>(find.byType(Pinput)).controller!.text;

  bool focused(WidgetTester tester) =>
      tester.widget<Pinput>(find.byType(Pinput)).focusNode!.hasFocus;

  testWidgets('the 4th digit sends the code by itself, once; a Verify tap '
      'while it is checked sends nothing more', (tester) async {
    PhoneVerification.debugWeb = false;
    await openCodeScreen(tester);
    expect(find.bySemanticsLabel('Verify'), findsOneWidget);

    await tester.enterText(codeField(), '987');
    await tester.pump();
    expect(client.verifyCodes, isEmpty, reason: 'three digits wait');

    await tester.enterText(codeField(), '9876');
    await tester.pump(const Duration(milliseconds: 50));
    expect(client.verifyCodes, ['9876'], reason: 'sent with no tap');

    // The Verify button stays; a tap during the check sends nothing.
    await tester.ensureVisible(find.bySemanticsLabel('Verify'));
    await tester.tap(find.bySemanticsLabel('Verify'), warnIfMissed: false);
    await tester.pump(latency * 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.verifyCodes, ['9876']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wrong code empties the boxes, keeps the error line and '
      'the focus; the next code is checked by itself', (tester) async {
    PhoneVerification.debugWeb = false;
    await openCodeScreen(tester);
    expect(focused(tester), isTrue);

    await tester.enterText(codeField(), '9999');
    await tester.pump(latency * 2);
    await tester.pump(const Duration(milliseconds: 100));

    expect(client.verifyCodes, ['9999']);
    expect(typed(tester), isEmpty, reason: 'the boxes are empty');
    expect(find.text(L10n.current.errWrongCode), findsOneWidget);
    expect(focused(tester), isTrue, reason: 'ready for the next code');

    // A second wrong code: again one call, again empty boxes.
    await tester.enterText(codeField(), '1111');
    await tester.pump(latency * 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.verifyCodes, ['9999', '1111']);
    expect(typed(tester), isEmpty);
    expect(find.text(L10n.current.errWrongCode), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in a browser: no focus by itself on open; after a wrong code '
      'checked with Verify too, the boxes empty and keep the focus', (
    tester,
  ) async {
    PhoneVerification.debugWeb = true;
    await openCodeScreen(tester);
    expect(focused(tester), isFalse, reason: 'no focus by itself on open');
    await tester.tap(find.byType(Pinput));
    await tester.pump(const Duration(milliseconds: 100));
    expect(focused(tester), isTrue);

    // Also when the rider taps Verify as well: the wrong code is checked
    // once, and the boxes are emptied.
    await tester.enterText(codeField(), '9999');
    await tester.pump();
    await tester.ensureVisible(find.bySemanticsLabel('Verify'));
    await tester.tap(find.bySemanticsLabel('Verify'), warnIfMissed: false);
    await tester.pump(latency * 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.verifyCodes, ['9999']);
    expect(find.text(L10n.current.errWrongCode), findsOneWidget);
    expect(typed(tester), isEmpty, reason: 'the boxes are empty');
    expect(focused(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
