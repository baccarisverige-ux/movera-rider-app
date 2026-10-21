// rider-u210: the trusted-contact editor padded itself by the keyboard
// height although MoveraSheet already does, so with the keyboard up the
// form shrank by twice the keyboard and left a 40-140 px strip to edit in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
  });

  testWidgets('the editor counts the keyboard once', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctl = SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      ),
    );
    await tester.runAsync(ctl.load);
    await tester.pumpWidget(
      MaterialApp(home: EmergencyContactsPage(controller: ctl)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle();

    Finder form() => find
        .ancestor(
          of: find.byType(TextField).first,
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(form(), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final rect = tester.getRect(form());
    // 640 - 280 keyboard - the sheet's own padding leaves well over 200 px.
    expect(rect.height, greaterThan(200));
    expect(rect.bottom, closeTo(640 - 280 - 20, 1));
  });
}
