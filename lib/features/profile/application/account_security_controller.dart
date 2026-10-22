import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/domain/account_security.dart';
import 'package:movera_rider/l10n/l10n.dart';

class AccountSecurityController extends ChangeNotifier {
  AccountSecurityController({required AccountSecurityRepository repository})
      : _repository = repository;

  final AccountSecurityRepository _repository;

  AccountSecurityState? state;
  bool loading = false;
  bool available = true;
  String? errorMessage;
  int _session = 0;

  /// Forgets the signed-out rider's security state. A load still in flight
  /// for that rider is ignored when it lands.
  void clearLocal() {
    _session += 1;
    state = null;
    loading = false;
    available = true;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> load() async {
    final session = _session;
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _repository.load();
      if (session != _session) return;
      state = loaded;
      available = true;
    } catch (_) {
      if (session != _session) return;
      state = null;
      available = false;
      // rider-59: shown on the Security screen, so in the app language.
      errorMessage = L10n.current.securityUnavailableBody;
    } finally {
      if (session == _session) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> signOutOtherDevices() async {
    final current = state;
    if (current == null ||
        !available ||
        !current.capabilities.signOutOtherDevices ||
        !current.capabilities.reauthentication ||
        !current.hasFreshReauthentication) {
      return;
    }
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      state = await _repository.signOutOtherDevices();
      available = true;
    } catch (_) {
      errorMessage = L10n.current.securitySessionsUpdateFailed;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
