import 'package:movera_rider/core/api/idempotency.dart';

/// Owns one idempotency key for one logical mutation intent.
///
/// A failed retry of the same intent reuses the key. Success clears it so a
/// later, genuinely new mutation can receive a fresh key.
class MutationAttempt {
  MutationAttempt(this.operation);

  final String operation;
  String? _intent;
  String? _key;
  int? _version;
  bool _versionPinned = false;

  String keyFor(String intent) {
    if (_intent == intent && _key != null) return _key!;
    _intent = intent;
    _key = newIdempotencyKey(operation);
    _version = null;
    _versionPinned = false;
    return _key!;
  }

  /// R-O2: the `expectedVersion` sent with this intent's key. It is fixed
  /// the first time the intent is sent ([current]), so a retry after a lost
  /// answer is the same request, not a second one for a newer version that
  /// the server would apply again.
  int? versionFor(String intent, int? current) {
    keyFor(intent);
    if (!_versionPinned) {
      _version = current;
      _versionPinned = true;
    }
    return _version;
  }

  void succeeded(String intent) {
    if (_intent != intent) return;
    reset();
  }

  /// Forget the key, for example after the server refused the intent as
  /// stale (nothing was applied): the next try is a new request.
  void reset() {
    _intent = null;
    _key = null;
    _version = null;
    _versionPinned = false;
  }
}
