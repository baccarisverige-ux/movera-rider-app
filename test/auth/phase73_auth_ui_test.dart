import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/add_phone.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in flow ("Moving to a new era"): phone -> code -> name for new riders;
/// Apple/Google riders add a phone once. Every path keeps the Phase 73 rule
/// that nothing reveals Home before the backend has accepted a code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  late MemoryTokenStore tokens;
  late InProcessMockClient client;
  late List<String?> pushed;

  AuthController controllerFor(InProcessMockClient c) {
    tokens = MemoryTokenStore();
    return AuthController(
      auth: AuthRepository(
        api: ApiClient(env: env, client: c, tokens: tokens),
        tokens: tokens,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Owner decision 7: the phone field starts in the device's country;
    // these riders' phones are set to Sweden (+46).
    tester.platformDispatcher.localeTestValue = const Locale('en', 'SE');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    pushed = [];
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: child,
          navigatorObservers: [_Pushes(pushed)],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Lets a push animation finish without waiting on screens that animate.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// PhoneVerification runs a countdown timer; unmount before the test ends.
  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  Future<void> typePhone(WidgetTester tester, String number) async {
    await tester.enterText(
      find.descendant(of: find.byType(AuthPhoneField), matching: find.byType(EditableText)),
      number,
    );
    await tester.pump();
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.tap(find.byType(Pinput));
    await tester.enterText(
      find.descendant(of: find.byType(Pinput), matching: find.byType(EditableText)),
      code,
    );
    await tester.pump();
  }

  /// True once Home was pushed. The test app's own first route is also
  /// named "/", so it is skipped.
  bool enteredApp() => pushed.skip(1).contains(AppRoutes.home);

  /// Scrolls a control into view first, as a rider would.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  testWidgets('failed code request stays on the phone step with a clear reason', (tester) async {
    client = InProcessMockClient()..failNext = true;
    await pump(tester, SignIn(controller: controllerFor(client)));

    await typePhone(tester, '701234567');
    await tapVisible(tester, find.text('Continue'));
    await settle(tester);

    expect(find.byType(SignIn), findsOneWidget);
    expect(find.byType(PhoneVerification), findsNothing);
    expect(find.textContaining('having trouble'), findsOneWidget);
  });

  testWidgets('wrong code says so and cannot reveal Home', (tester) async {
    client = InProcessMockClient();
    final controller = controllerFor(client);
    final challenge = await controller.requestOtp(phone: '+46701234567');
    await pump(tester, PhoneVerification(challenge: challenge, controller: controller));

    await typeCode(tester, '9999');
    await tapVisible(tester, find.text('Verify'));
    await settle(tester);

    expect(find.byType(PhoneVerification), findsOneWidget);
    expect(find.textContaining("isn't right"), findsOneWidget);
    expect(find.byType(Home, skipOffstage: false), findsNothing);
    expect(enteredApp(), isFalse);
    expect(await tokens.readAccess(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'Phase 132 cluster 4: the phone step rejects a too-short number the old '
    'length-only check would have accepted',
    (tester) async {
      client = InProcessMockClient();
      await pump(tester, SignIn(controller: controllerFor(client)));

      await typePhone(tester, '12345');
      await tapVisible(tester, find.text('Continue'));
      await tester.pump();

      expect(find.byType(PhoneVerification), findsNothing);
      expect(find.textContaining('valid mobile number'), findsOneWidget);
    },
  );

  testWidgets(
    'Phase 132 cluster 4: the Apple/Google phone step applies the same check',
    (tester) async {
      client = InProcessMockClient();
      await pump(
        tester,
        AddPhoneNumber(
          link: const ProviderLink(provider: 'apple', linkToken: 'link_unused'),
          controller: controllerFor(client),
        ),
      );

      await typePhone(tester, '12345');
      await tapVisible(tester, find.text('Send code'));
      await tester.pump();

      expect(find.byType(PhoneVerification), findsNothing);
      expect(find.textContaining('valid mobile number'), findsOneWidget);
    },
  );

  testWidgets(
    'an everyday "070..." number is sent as +4670..., not the old +46070...',
    (tester) async {
      client = InProcessMockClient();
      await pump(tester, SignIn(controller: controllerFor(client)));

      await typePhone(tester, '070 123 45 67');
      await tapVisible(tester, find.text('Continue'));
      await settle(tester);

      expect(find.byType(PhoneVerification), findsOneWidget);
      expect(find.textContaining('+46 70 123 45 67', findRichText: true), findsOneWidget);
      final session = client.otpSessions.values.single;
      expect(session['phone'], '+46701234567');
      await unmount(tester);
    },
  );

  testWidgets('auth-required start shows the phone step, never Home', (tester) async {
    client = InProcessMockClient();
    await pump(tester, SignIn(controller: controllerFor(client)));

    expect(find.byType(AuthPhoneField), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing); // label is "Apple"
    expect(find.bySemanticsLabel('Continue with Apple'), findsOneWidget);
    expect(find.byType(Home, skipOffstage: false), findsNothing);
  });

  testWidgets('a new rider goes phone -> code -> name, then into the app', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    client = InProcessMockClient();
    final controller = controllerFor(client);
    await pump(tester, SignIn(controller: controller));

    await typePhone(tester, '701234567');
    await tapVisible(tester, find.text('Continue'));
    await settle(tester);
    await typeCode(tester, '1234');
    await tapVisible(tester, find.text('Verify'));
    await settle(tester);

    expect(find.byType(RiderNameScreen), findsOneWidget);
    expect(enteredApp(), isFalse);
    expect(await tokens.readAccess(), startsWith('mock-access-phone-'));

    await tapVisible(tester, find.text("Let's ride"));
    await tester.pump();
    expect(find.textContaining('Enter your first name'), findsOneWidget);
    expect(enteredApp(), isFalse);

    final fields = find.descendant(
      of: find.byType(AuthTextField),
      matching: find.byType(EditableText),
    );
    await tester.enterText(fields.at(0), 'Sara');
    await tester.enterText(fields.at(1), 'Lind');
    await tapVisible(tester, find.text("Let's ride"));
    await tester.pump();
    await tester.pump();

    expect(AppScope.instance.profile.profile.name, 'Sara Lind');
    expect(enteredApp(), isTrue);
    await unmount(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a returning rider skips the name step', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    client = InProcessMockClient()..knownPhones.add('+46701234567');
    await pump(tester, SignIn(controller: controllerFor(client)));

    await typePhone(tester, '701234567');
    await tapVisible(tester, find.text('Continue'));
    await settle(tester);
    await typeCode(tester, '1234');
    await tapVisible(tester, find.text('Verify'));
    await tester.pump();
    await tester.pump();

    expect(enteredApp(), isTrue);
    expect(find.byType(RiderNameScreen, skipOffstage: false), findsNothing);
    await unmount(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'first Apple sign-in requires a phone and saves no session until the '
    'code is verified',
    (tester) async {
      client = InProcessMockClient();
      await pump(tester, SignIn(controller: controllerFor(client)));

      await tapVisible(tester, find.bySemanticsLabel('Continue with Apple'));
      await settle(tester);

      expect(find.byType(AddPhoneNumber), findsOneWidget);
      expect(find.text('Signed in with Apple'), findsOneWidget);
      expect(await tokens.readAccess(), isNull);
      expect(enteredApp(), isFalse);

      await typePhone(tester, '701234567');
      await tapVisible(tester, find.text('Send code'));
      await settle(tester);
      expect(find.byType(PhoneVerification), findsOneWidget);
      expect(await tokens.readAccess(), isNull);

      await typeCode(tester, '1234');
      await tapVisible(tester, find.text('Verify'));
      await settle(tester);

      expect(await tokens.readAccess(), startsWith('mock-access-apple-'));
      expect(client.linkedProviders, contains('apple'));
      expect(find.byType(RiderNameScreen), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('leaving the Apple phone step half-way leaves no session', (tester) async {
    client = InProcessMockClient();
    await pump(tester, SignIn(controller: controllerFor(client)));

    await tapVisible(tester, find.bySemanticsLabel('Continue with Apple'));
    await settle(tester);
    expect(find.byType(AddPhoneNumber), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.byType(SignIn), findsOneWidget);
    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
  });

  testWidgets('a returning Google rider with a verified phone goes straight in', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    client = InProcessMockClient()..linkedProviders.add('google');
    await pump(tester, SignIn(controller: controllerFor(client)));

    await tapVisible(tester, find.bySemanticsLabel('Continue with Google'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AddPhoneNumber, skipOffstage: false), findsNothing);
    expect(enteredApp(), isTrue);
    expect(await tokens.readAccess(), 'mock-access-google');
    await unmount(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a failed Apple sign-in explains why and stays put', (tester) async {
    client = InProcessMockClient()..failNext = true;
    await pump(tester, SignIn(controller: controllerFor(client)));

    await tapVisible(tester, find.bySemanticsLabel('Continue with Apple'));
    await settle(tester);

    expect(find.byType(SignIn), findsOneWidget);
    expect(find.textContaining('having trouble'), findsOneWidget);
    expect(await tokens.readAccess(), isNull);
  });
}

class _Pushes extends NavigatorObserver {
  _Pushes(this.names);

  final List<String?> names;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    names.add(newRoute?.settings.name);
  }
}
