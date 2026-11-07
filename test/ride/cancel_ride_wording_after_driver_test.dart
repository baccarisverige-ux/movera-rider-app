import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner 2026-11-07: the cancel confirm said « Avbryt förfrågan » (cancel
/// request) after a driver was assigned (Waiting). Once a driver is on the
/// ride the button cancels the ride; while searching it stays the request.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Locale locale, CancelPhase phase) {
    // The app's strings follow the rider's language (L10n.use).
    L10n.use(locale.languageCode);
    addTearDown(() => L10n.use('en'));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CancelRideSheet(takingLonger: false, phase: phase),
        ),
      ),
    );
  }

  for (final code in ['sv', 'fr', 'en']) {
    final l10n = lookupAppLocalizations(Locale(code));
    testWidgets('$code: driver assigned -> "${l10n.cancelRide}"', (
      tester,
    ) async {
      await pump(tester, Locale(code), CancelPhase.matched);
      expect(find.text(l10n.cancelRide), findsOneWidget);
      expect(find.text(l10n.cancelRequest), findsNothing);
    });
    testWidgets('$code: still searching -> "${l10n.cancelRequest}"', (
      tester,
    ) async {
      await pump(tester, Locale(code), CancelPhase.searching);
      expect(find.text(l10n.cancelRequest), findsOneWidget);
    });
  }
}
