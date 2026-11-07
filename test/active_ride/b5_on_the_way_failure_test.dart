// B5 (finder 2026-11-07, fail-before on main): "I'm on the way" on the
// Driver arrived sheet did nothing when the call failed (offline, or 409
// invalid_transition because the trip had moved on): the sheet stayed open,
// no message, and the error was uncaught. Finder B's test, plus the 409 and
// success cases.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

Future<void> _openAndTap(
  WidgetTester tester,
  Future<void> Function() onWay,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDriverArrivedSheet(context, onWay: onWay),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(DriverArrivedSheet), findsOneWidget);
  final button = find.widgetWithText(FilledButton, L10n.current.imOnTheWay);
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a failing on-the-way call still closes the sheet', (
    tester,
  ) async {
    await _openAndTap(tester, () async => throw StateError('offline'));
    final thrown = tester.takeException();
    expect(
      find.byType(DriverArrivedSheet),
      findsNothing,
      reason: 'sheet still open after the tap; uncaught: $thrown',
    );
    expect(thrown, isNull);
  });

  testWidgets('offline: the sheet closes and says Movera was not reached', (
    tester,
  ) async {
    await _openAndTap(
      tester,
      () async => throw const ApiError(code: 'NETWORK', message: 'offline'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(DriverArrivedSheet), findsNothing);
    expect(find.text(L10n.current.apiUnreachable), findsOneWidget);
  });

  testWidgets('409 (the trip moved on): the sheet closes, no error', (
    tester,
  ) async {
    await _openAndTap(
      tester,
      () async => throw const ApiError(
        code: 'invalid_transition',
        message: 'invalid_transition',
        statusCode: 409,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(DriverArrivedSheet), findsNothing);
    expect(find.text(L10n.current.apiUnreachable), findsNothing);
  });

  testWidgets('success: the sheet closes, no error', (tester) async {
    var sent = 0;
    await _openAndTap(tester, () async => sent++);
    expect(sent, 1);
    expect(find.byType(DriverArrivedSheet), findsNothing);
    expect(find.text(L10n.current.apiUnreachable), findsNothing);
  });
}
