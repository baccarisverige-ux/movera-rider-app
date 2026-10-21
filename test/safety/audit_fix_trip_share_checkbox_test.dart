// rider-85: a trusted-contact checkbox on Trip share whose save failed gave
// the rider no feedback, editContact's error escaped unhandled, and a
// partial failure left the selection list and the contact's "Share trips"
// out of step.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contact updates fail while [down]; everything else works.
class _Remote extends ApiSafetyRemoteDataSource {
  _Remote(super.api);
  bool down = false;

  @override
  Future<EmergencyContact> updateContact(EmergencyContact contact) async {
    if (down) throw const SafetyException('SERVER_ERROR', 'offline');
    return super.updateContact(contact);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late _Remote remote;
  late SafetyStore store;
  late SafetyController ctl;
  void Function() restoreErrors = () {};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  /// The page's tiles sit in a coloured card, which trips Flutter's debug
  /// "ListTile ink splashes may be invisible" check (an existing look, not
  /// what this test is about). Any other error still fails the test.
  void ignoreTileInkCheck(WidgetTester tester) {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('ink splashes may be invisible')) return;
      original?.call(details);
    };
    restoreErrors = () {
      FlutterError.onError = original;
    };
  }

  Future<void> pumpPage(WidgetTester tester) async {
    remote = _Remote(ApiClient(client: InProcessMockClient()));
    store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: remote,
    );
    ctl = SafetyController(session: store);
    await tester.runAsync(() async {
      await ctl.load();
      await ctl.addContact(name: 'Kim', phone: '0701234567');
      await ctl.setTripShare(enabled: true);
    });
    ignoreTileInkCheck(tester);
    await tester.pumpWidget(MaterialApp(home: TripSharePage(controller: ctl)));
    await tester.pumpAndSettle();
  }

  Future<void> tapKim(WidgetTester tester) async {
    final box = find.widgetWithText(CheckboxListTile, 'Kim');
    await tester.ensureVisible(box);
    await tester.tap(box);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a failed selection save says so and changes nothing', (
    tester,
  ) async {
    await pumpPage(tester);
    store.failNextWrite = true;
    await tapKim(tester);
    expect(find.text('Could not update trip sharing.'), findsOneWidget);
    expect(ctl.preferences.tripShareContactIds, isEmpty);
    expect(ctl.contacts.single.shareTrips, isFalse);
    restoreErrors();
  });

  testWidgets('a failed contact save is reported and the selection undone', (
    tester,
  ) async {
    await pumpPage(tester);
    remote.down = true;
    await tapKim(tester);
    expect(find.text('Could not update trip sharing.'), findsOneWidget);
    expect(
      ctl.preferences.tripShareContactIds,
      isEmpty,
      reason: 'the list and Share trips must agree',
    );
    expect(ctl.contacts.single.shareTrips, isFalse);
    final box = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Kim'),
    );
    expect(box.value, isFalse);
    restoreErrors();
  });
}
