import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-u228: the date/time step's Continue was read out as the English
/// test label "Schedule Continue" in every language, never as "Continuing…"
/// while busy, and had no tap action for a screen reader to activate.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  tearDown(() => L10n.use('en'));

  testWidgets('Continue reads in the app language and can be activated', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    L10n.use('sv');
    final sv = lookupAppLocalizations(const Locale('sv'));
    var confirms = 0;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          now: () => DateTime.utc(2026, 9, 26, 10),
          onConfirm: () => confirms += 1,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Schedule Continue'), findsNothing);
    final node = find.bySemanticsLabel(sv.continueLabel);
    expect(node, findsOneWidget);
    final data = tester.getSemantics(node).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    tester.semantics.tap(find.semantics.byLabel(sv.continueLabel));
    await tester.pump();
    expect(confirms, 1);
    semantics.dispose();
  });
}
