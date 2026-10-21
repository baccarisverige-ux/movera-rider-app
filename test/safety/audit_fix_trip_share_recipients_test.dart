// rider-u204: Share trip sent the trip to the stored tripShareContactIds
// whenever that list was non-empty, so deleted or disabled contacts were
// sent the trip and contacts marked "Share trips" were left out.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SafetyController safety;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    safety = SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      ),
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    );
    await safety.load();
    await safety.setTripShare(enabled: true);
  });

  String idOf(String name) =>
      safety.contacts.firstWhere((c) => c.name == name).id;

  /// What the Trip share page's checkbox does.
  Future<void> tick(String name, bool value) async {
    final id = idOf(name);
    final selected = [...safety.preferences.tripShareContactIds];
    value ? selected.add(id) : selected.remove(id);
    await safety.setTripShare(contactIds: selected);
    await safety.editContact(
      safety.contacts.firstWhere((c) => c.id == id).copyWith(shareTrips: value),
    );
  }

  test(
    'a deleted contact is not sent the trip; one marked Share trips is',
    () async {
      await safety.addContact(name: 'Anna', phone: '0701234561');
      await tick('Anna', true);
      final anna = idOf('Anna');
      await safety.removeContact(anna);
      await safety.addContact(
        name: 'Bo',
        phone: '0701234562',
        shareTrips: true,
      );

      final share = await safety.startShare('r1');
      expect(share.contactIds, [idOf('Bo')]);
    },
  );

  test(
    'a contact switched off in the editor or disabled is not sent the trip',
    () async {
      await safety.addContact(name: 'Anna', phone: '0701234561');
      await safety.addContact(name: 'Cleo', phone: '0701234563');
      await safety.addContact(name: 'Dan', phone: '0701234564');
      await tick('Anna', true);
      await tick('Cleo', true);
      await tick('Dan', true);

      // The contact editor's "Share trips" switch turns Anna off.
      await safety.editContact(
        safety.contacts
            .firstWhere((c) => c.name == 'Anna')
            .copyWith(shareTrips: false),
      );
      expect(
        safety.preferences.tripShareContactIds,
        isNot(contains(idOf('Anna'))),
      );
      // Cleo is disabled.
      await safety.editContact(
        safety.contacts
            .firstWhere((c) => c.name == 'Cleo')
            .copyWith(isEnabled: false),
      );

      final share = await safety.startShare('r1');
      expect(share.contactIds, [idOf('Dan')]);
    },
  );
}
