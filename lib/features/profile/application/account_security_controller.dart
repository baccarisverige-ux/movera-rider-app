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
  /// rider-r5-46: what went wrong, put into words when it is shown, so
  /// the line follows a language switch.
  _SecurityError? _error;
  String? get errorMessage => switch (_error) {
    null => null,
    _SecurityError.unavailable => L10n.current.securityUnavailableBody,
    _SecurityError.reauth => L10n.current.reauthBeforeRevoke,
    _SecurityError.updateFailed => L10n.current.securitySessionsUpdateFailed,
  };
  int _session = 0;

  /// Forgets the signed-out rider's security state. A load still in flight
  /// for that rider is ignored when it lands.
  void clearLocal() {
    _session += 1;
    state = null;
    loading = false;
    available = true;
    _error = null;
    notifyListeners();
  }

  Future<void> load() async {
    final session = _session;
    loading = true;
    _error = null;
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
      _error = _SecurityError.unavailable;
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
        !current.capabilities.reauthentication) {
      return;
    }
    // rider-u156: the page may have been open past the 5-minute window;
    // say so instead of doing nothing.
    if (!current.hasFreshReauthentication) {
      _error = _SecurityError.reauth;
      notifyListeners();
      return;
    }
    loading = true;
    _error = null;
    notifyListeners();
    try {
      state = await _repository.signOutOtherDevices();
      available = true;
    } catch (_) {
      _error = _SecurityError.updateFailed;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

enum _SecurityError { unavailable, reauth, updateFailed }
