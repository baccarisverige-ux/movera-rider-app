import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/profile/data/account_repository.dart';

/// Delete account (FLOW-2): asks the backend to delete the account, then
/// ends the session and wipes this device like Sign out does.
class AccountDeletionController {
  AccountDeletionController({
    AccountRepository? repository,
    AuthController? auth,
    PushService? push,
  }) : _repository = repository ?? AccountRepository(),
       _auth = auth ?? AppScope.instance.auth,
       _push = push;

  final AccountRepository _repository;
  final AuthController _auth;
  final PushService? _push;

  /// Throws when the backend did not accept the request; nothing is wiped
  /// then, so the rider can try again.
  Future<void> requestDeletion() async {
    await _repository.requestDeletion();
    // rider-r5-43: the deletion is only scheduled, so the device is not
    // known to be revoked. As on Sign out, the push token is dropped (and
    // the inbound streams detached) best effort before the wipe.
    try {
      await (_push ?? AppScope.instance.push).unregister();
    } catch (error) {
      AppLog.warning(
        'account.push_unregister_deferred',
        extra: {'error': error.toString()},
      );
    }
    await _auth.signOutLocally();
  }
}
