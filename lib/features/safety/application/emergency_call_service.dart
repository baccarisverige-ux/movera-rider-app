import 'package:url_launcher/url_launcher.dart';
import 'package:movera_rider/l10n/l10n.dart';

typedef EmergencyUriLauncher = Future<bool> Function(Uri uri);

class EmergencyCallException implements Exception {
  const EmergencyCallException(this.message);

  final String message;

  @override
  String toString() => 'EmergencyCallException($message)';
}

/// Opens the system dialer. Never invoked automatically.
abstract class EmergencyDialer {
  Future<void> open(String number);
}

/// Production dialer. It requests the platform to open an external `tel:` URI.
class SystemEmergencyDialer implements EmergencyDialer {
  SystemEmergencyDialer({EmergencyUriLauncher? launcher})
    : _launcher = launcher ?? _launch;

  final EmergencyUriLauncher _launcher;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<void> open(String number) async {
    final clean = number.trim();
    if (clean.isEmpty) {
      throw EmergencyCallException(L10n.current.emergencyNumberUnavailable);
    }
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      final opened = await _launcher(uri);
      if (!opened) {
        throw EmergencyCallException(L10n.current.dialerOpenFailed);
      }
    } on EmergencyCallException {
      rethrow;
    } catch (_) {
      throw EmergencyCallException(L10n.current.dialerOpenFailed);
    }
  }
}

/// Test-only dialer. Release composition rejects this outside dev/test.
class RecordingEmergencyDialer implements EmergencyDialer {
  final calls = <String>[];

  @override
  Future<void> open(String number) async {
    calls.add(number);
  }
}

class EmergencyCallService {
  EmergencyCallService({EmergencyDialer? dialer})
    : _dialer = dialer ?? SystemEmergencyDialer();

  static final EmergencyCallService shared = EmergencyCallService();

  static const swedenEmergencyNumber = '112';

  final EmergencyDialer _dialer;
  int _explicitCalls = 0;

  int get explicitCallCount => _explicitCalls;
  EmergencyDialer get dialer => _dialer;
  bool get usesRecordingDialer => _dialer is RecordingEmergencyDialer;

  /// Requires an explicit rider action. Never called from background logic.
  Future<void> callEmergencyNumber() async {
    _explicitCalls += 1;
    await _dialer.open(swedenEmergencyNumber);
  }
}
