import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner round 3: the terms must be ticked before sign-in continues, and the
// Terms and Privacy pages carry the full texts in every language.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String locale = 'en',
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // context.l10n reads L10n.current, as the app does.
    L10n.use(locale);
    addTearDown(() => L10n.use('en'));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<AuthPrimaryButton>(button).onPressed != null;

  testWidgets('Continue, Apple and Google wait for the tick', (tester) async {
    await pump(tester, const SignIn());
    final consent = find.byKey(const ValueKey('auth-consent'));
    expect(consent, findsOneWidget);
    expect(
      find.textContaining('By continuing', findRichText: true), // G1-B5
      findsOneWidget,
    );
    expect(enabled(tester, find.byType(AuthPrimaryButton)), isFalse);
    for (final provider in ['Apple', 'Google']) {
      final button = tester.widget<AuthProviderButton>(
        find.widgetWithText(AuthProviderButton, provider),
      );
      expect(button.onPressed, isNull, reason: provider);
    }

    // Tapping Continue while unticked only nudges.
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(AuthPrimaryButton), findsOneWidget);

    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(enabled(tester, find.byType(AuthPrimaryButton)), isTrue);
    for (final provider in ['Apple', 'Google']) {
      final button = tester.widget<AuthProviderButton>(
        find.widgetWithText(AuthProviderButton, provider),
      );
      expect(button.onPressed, isNotNull, reason: provider);
    }

    // Untick again: back to waiting.
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(enabled(tester, find.byType(AuthPrimaryButton)), isFalse);
  });

  testWidgets('the consent row is a checkbox for screen readers', (
    tester,
  ) async {
    await pump(tester, const SignIn());
    final handle = tester.ensureSemantics();
    final consent = find.byKey(const ValueKey('auth-consent'));
    final before = tester.getSemantics(consent);
    expect(before.flagsCollection.isChecked, CheckedState.isFalse);
    expect(before.label, 'I accept the terms and the privacy policy'); // G1-B5
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(consent).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    handle.dispose();
  });

  testWidgets('the legal pages carry the full texts in en, fr and sv', (
    tester,
  ) async {
    for (final (locale, termsTitle, privacyTitle) in const [
      ('en', 'Who we are', 'Who is responsible'),
      ('fr', 'Qui nous sommes', 'Qui est responsable'),
      ('sv', 'Vilka vi är', 'Vem som ansvarar'),
    ]) {
      await pump(tester, const AccountLegalPage(kind: 'terms'), locale: locale);
      expect(find.textContaining(termsTitle), findsOneWidget, reason: locale);
      expect(
        find.textContaining('[', findRichText: true),
        findsWidgets,
        reason: 'company details are placeholders until the owner fills them',
      );
      await pump(
        tester,
        const AccountLegalPage(kind: 'privacy'),
        locale: locale,
      );
      expect(find.textContaining(privacyTitle), findsOneWidget, reason: locale);
    }
  });

  test('every language has the same sections, with no empty text', () async {
    for (final code in L10n.codes) {
      final l = await AppLocalizations.delegate.load(Locale(code));
      final terms = AccountLegalPage.sections(l, terms: true);
      final privacy = AccountLegalPage.sections(l, terms: false);
      // v0.16.0: + "Crash and error reports" (owner 2026-10-29).
      expect(terms, hasLength(14), reason: code);
      expect(privacy, hasLength(12), reason: code);
      for (final s in [...terms, ...privacy]) {
        expect(s.title.trim(), isNotEmpty, reason: code);
        expect(
          s.body.trim().length,
          greaterThan(40),
          reason: '$code ${s.title}',
        );
      }
      // Stores look for these: deletion, children, contact, data shared.
      final all = [...terms, ...privacy].map((s) => s.body).join(' ');
      expect(all, contains('IMY'), reason: code);
      expect(all, contains('112'), reason: code);
    }
  });
}
