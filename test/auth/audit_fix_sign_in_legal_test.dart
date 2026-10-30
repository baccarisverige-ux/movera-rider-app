import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FLOW-16: "By continuing you agree to our Terms and Privacy Policy" links
/// to both texts, and the texts say they are a summary.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TextSpan spanFor(WidgetTester tester, String text) {
    TextSpan? found;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == text) found = span;
        return found == null;
      });
      if (found != null) break;
    }
    return found!;
  }

  for (final (link, kind) in [
    ('terms', 'terms'), // G1-B5: the owner's sentence
    ('privacy policy', 'privacy'),
  ]) {
    testWidgets('"$link" on Sign in opens the $kind page', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tokens = MemoryTokenStore();
      final auth = AuthController(
        auth: AuthRepository(
          api: ApiClient(client: InProcessMockClient(), tokens: tokens),
          tokens: tokens,
        ),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(home: SignIn(controller: auth)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // G1-B6: Terms and Privacy are their own links under the consent
      // line (the line itself only ticks the box).
      expect(spanFor(tester, link).recognizer, isNull);
      final button = find.byKey(ValueKey('auth-legal-$kind'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final page = tester.widget<AccountLegalPage>(
        find.byType(AccountLegalPage),
      );
      expect(page.kind, kind);
      expect(
        find.textContaining(
          kind == 'terms' ? 'Who we are' : 'Who is responsible',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
