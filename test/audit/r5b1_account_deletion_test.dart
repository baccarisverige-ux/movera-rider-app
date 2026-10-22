import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/profile/application/account_deletion_controller.dart';
import 'package:movera_rider/features/profile/data/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends AccountRepository {
  @override
  Future<AccountDeletionRequest> requestDeletion() async =>
      const AccountDeletionRequest(status: 'scheduled');
}

class _Auth extends AuthController {
  final calls = <String>[];
  @override
  Future<void> signOutLocally() async => calls.add('wipe');
}

class _Push implements PushService {
  _Push(this.calls);
  final List<String> calls;
  @override
  Future<void> register() async {}
  @override
  Future<void> unregister() async {
    calls.add('unregister');
    throw StateError('offline');
  }
  @override
  Stream<PushPayload> get foregroundMessages => const Stream.empty();
  @override
  Stream<PushPayload> get openedMessages => const Stream.empty();
  @override
  Future<PushPayload?> takeInitialMessage() async => null;
}

void main() {
  test('rider-r5-43: account deletion unregisters push before the wipe',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = _Auth();
    await AccountDeletionController(
      repository: _Repo(),
      auth: auth,
      push: _Push(auth.calls),
    ).requestDeletion();
    expect(auth.calls, ['unregister', 'wipe']);
  });
}
