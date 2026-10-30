import 'package:flutter/foundation.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.5 `auth.signedOut.kinds`.
enum SignedOutKind { expired, revoked }

/// Why the rider was signed out, for the sign-in screen (contract v0.18.5
/// `auth.signedOut`, owner G1-D3 "Show a message (Recommended)").
class SignedOut {
  const SignedOut(this.kind, {this.withDetail = true});

  final SignedOutKind kind;

  /// False when the refused refresh named no known reason: the headline
  /// only, no guessed reason line.
  final bool withDetail;

  String get text => switch (kind) {
    SignedOutKind.expired => L10n.current.signedOutExpired,
    SignedOutKind.revoked => L10n.current.signedOutRevoked,
  };

  String? get detail => !withDetail
      ? null
      : switch (kind) {
          SignedOutKind.expired => L10n.current.signedOutDetailExpired,
          SignedOutKind.revoked => L10n.current.signedOutDetailRevoked,
        };

  @override
  bool operator ==(Object other) =>
      other is SignedOut &&
      other.kind == kind &&
      other.withDetail == withDetail;

  @override
  int get hashCode => Object.hash(kind, withDetail);
}

/// Set when `POST /auth/refresh` answers 401 and the app signs the rider
/// out; read by the sign-in screen; cleared by the rider's own Sign out
/// (`auth.signedOut.ownSignOut`: no message then), a new sign-in try and a
/// successful sign-in.
abstract final class SignedOutNotice {
  static final ValueNotifier<SignedOut?> current = ValueNotifier(null);

  /// `contract.json#auth.signedOut.reasons`.
  static const reasons = <String, SignedOutKind>{
    'session_expired': SignedOutKind.expired,
    'session_ended': SignedOutKind.revoked,
    'refresh_token_reused': SignedOutKind.revoked,
    'refresh_token_unknown': SignedOutKind.revoked,
  };

  /// The notice for a refused refresh with [reason].
  static SignedOut forReason(String? reason) {
    final kind = reasons[reason];
    return kind == null
        ? const SignedOut(SignedOutKind.expired, withDetail: false)
        : SignedOut(kind);
  }

  static void clear() => current.value = null;
}
