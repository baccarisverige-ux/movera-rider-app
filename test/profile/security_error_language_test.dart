import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-r5-46: the Security page's error line is in the language in use
/// when it is shown, not the one in use when the error happened.
void main() {
  tearDown(() => L10n.use('en'));

  test('the error follows a language switch', () async {
    L10n.use('sv');
    final client = InProcessMockClient();
    client.accountSecurity
      ..['reauthenticatedAt'] = null
      ..['capabilities'] = {
        ...client.accountSecurity['capabilities'] as Map,
        'reauthentication': true,
        'signOutOtherDevices': true,
      };
    final controller = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.test,
            apiBaseUrl: 'https://api.test.movera.invalid',
          ),
          client: client,
        ),
      ),
    );
    await controller.load();
    await controller.signOutOtherDevices();
    expect(controller.errorMessage, L10n.current.reauthBeforeRevoke);

    L10n.use('fr');
    expect(controller.errorMessage, L10n.current.reauthBeforeRevoke);
  });
}
