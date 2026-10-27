import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// Audit Phase 5: the Safety screen with its new "cannot be saved yet" note
/// on a small phone, with large text, in each app language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );

  for (final locale in const [Locale('sv'), Locale('fr'), Locale('en')]) {
    for (final (size, scale) in const [
      (Size(320, 568), 1.0),
      (Size(320, 568), 2.0),
      (Size(390, 844), 1.3),
    ]) {
      testWidgets('Safety note, ${locale.languageCode}, '
          '${size.width.toInt()}x${size.height.toInt()} at ${scale}x', (
        tester,
      ) async {
        final api = ApiClient(
          env: live,
          client: MockClient((_) async => http.Response('{}', 500)),
        );
        L10n.use(locale.languageCode);
        addTearDown(() => L10n.use('en'));
        final ctl = SafetyController(session: SafetyStore(api: api));
        final errors = await collectFlutterErrors(() async {
          await pumpMoveraScreen(
            tester,
            SafetyHub(controller: ctl),
            viewport: size,
            textScale: scale,
            locale: locale,
          );
          await tester.pumpAndSettle();
        });
        expect(errors, isEmpty);
        final l10n = await AppLocalizations.delegate.load(locale);
        final note = find.text(l10n.safetyNotOnServer);
        // Above the rows it explains: reached before any of them.
        await tester.scrollUntilVisible(
          note,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(note, findsOneWidget);
        final firstRow = find.text(l10n.safetyPinTitle);
        if (firstRow.evaluate().isNotEmpty) {
          expect(
            tester.getTopLeft(note).dy,
            lessThan(tester.getTopLeft(firstRow).dy),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
