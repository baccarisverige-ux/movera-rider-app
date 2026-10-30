import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/keyboard_anchor.dart';
import 'package:pinput/pinput.dart';

/// Owner 2026-10-30 (screen video, rider sign-in on an iPhone): "When clic
/// on any box to fill, why the botton continue doesnt show up with
/// keyboard!?" The field, the terms tick and Continue (Verify on the code
/// screen) must sit above the keyboard while typing.
///
/// The keyboard is simulated the way Flutter web reports it on iPhone
/// Safari and Android Chrome (and the OS in the store apps): a bottom view
/// inset while a field is edited, the view itself keeping its full size.
const _screen = Size(390, 844);

/// An iPhone 13/14 number keyboard with its bar, in logical pixels.
const _keyboard = 336.0;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _openKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Fully on screen and above the keyboard.
void _expectAboveKeyboard(WidgetTester tester, Finder finder, String what) {
  final rect = tester.getRect(finder);
  expect(
    rect.bottom,
    lessThanOrEqualTo(_screen.height - _keyboard + 0.5),
    reason: '$what is under the keyboard ($rect)',
  );
  expect(rect.top, greaterThanOrEqualTo(-0.5), reason: '$what is off the top');
}

Widget _app(Widget home) => ScreenUtilInit(
  designSize: _screen,
  builder: (_, __) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => PhoneVerification.debugWeb = null);

  testWidgets('sign-in: the phone field, the terms tick and Continue stay '
      'above the keyboard', (tester) async {
    _phone(tester);
    final tokens = MemoryTokenStore();
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.test.movera.invalid',
      ),
      client: MockClient((_) async => http.Response('{}', 404)),
      tokens: tokens,
    );
    await tester.pumpWidget(
      _app(
        SignIn(
          controller: AuthController(
            auth: AuthRepository(api: api, tokens: tokens),
          ),
          showTestAccounts: false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));

    final field = find.byType(EditableText).first;
    await tester.showKeyboard(field);
    await _openKeyboard(tester);

    _expectAboveKeyboard(tester, field, 'the phone field');
    _expectAboveKeyboard(
      tester,
      find.byKey(const ValueKey('auth-consent')),
      'the terms tick',
    );
    _expectAboveKeyboard(
      tester,
      find.text(L10n.current.continueLabel),
      'Continue',
    );
  });

  testWidgets('code screen: the code boxes and Verify stay above the '
      'keyboard', (tester) async {
    final tokens = MemoryTokenStore();
    final auth = AuthController(
      auth: AuthRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.test,
            apiBaseUrl: 'https://api.test.movera.invalid',
          ),
          client: InProcessMockClient(latency: Duration.zero),
          tokens: tokens,
        ),
        tokens: tokens,
      ),
    );
    final challenge = (await tester.runAsync(
      () => auth.requestOtp(phone: '+46701234567'),
    ))!;
    _phone(tester);
    await tester.pumpWidget(
      _app(PhoneVerification(challenge: challenge, controller: auth)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final code = find.descendant(
      of: find.byType(Pinput),
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(code);
    await _openKeyboard(tester);

    _expectAboveKeyboard(tester, find.byType(Pinput), 'the code boxes');
    _expectAboveKeyboard(tester, find.text(L10n.current.verify), 'Verify');
  });

  testWidgets('any form: the button wrapped in KeyboardAnchor is lifted '
      'above the keyboard, the field stays on screen', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 420),
                const TextField(key: ValueKey('field')),
                const SizedBox(height: 260),
                KeyboardAnchor(
                  child: FilledButton(
                    key: const ValueKey('save'),
                    onPressed: () {},
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byKey(const ValueKey('field')));
    await _openKeyboard(tester);

    _expectAboveKeyboard(tester, find.byKey(const ValueKey('field')), 'field');
    _expectAboveKeyboard(tester, find.byKey(const ValueKey('save')), 'Save');
  });

  testWidgets('no keyboard: nothing moves', (tester) async {
    _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const TextField(key: ValueKey('field')),
                const SizedBox(height: 1200),
                KeyboardAnchor(
                  child: FilledButton(onPressed: () {}, child: const Text('x')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byKey(const ValueKey('field')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, 0);
  });
}
