import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Sign out (FLOW-2, NAV-4): confirm, end the session, wipe this device and
/// show Sign in at the app root. Shared by the Account page and the menu.
Future<void> confirmAndSignOut(
  BuildContext context, {
  AuthController? auth,
}) async {
  // rider-u76: a second tap while a sign-out runs does nothing.
  if (_signingOut) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        context.l10n.signOutQ,
        style: GoogleFonts.urbanist(fontWeight: FontWeight.w700),
      ),
      content: Text(
        context.l10n.signOutQBody,
        style: GoogleFonts.urbanist(fontSize: 13.5),
      ),
      actions: [
        TextButton(
          key: const ValueKey('sign-out-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('sign-out-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.l10n.accountSignOut),
        ),
      ],
    ),
  );
  if (confirmed != true || _signingOut) return;
  _signingOut = true;
  try {
    // rider-u76: the flush, push unregister and server sign-out can take
    // a while on a slow network. Until Sign in shows (which closes this),
    // the rider sees progress and cannot book or tap around meanwhile.
    if (navigator.mounted) {
      unawaited(
        showDialog<void>(
          context: navigator.context,
          barrierDismissible: false,
          builder: (_) => const _SigningOut(),
        ),
      );
    }
    await signOutAndShowSignIn(auth: auth, navigator: navigator);
  } finally {
    _signingOut = false;
  }
}

bool _signingOut = false;

class _SigningOut extends StatelessWidget {
  const _SigningOut();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                context.l10n.signingOut,
                style: GoogleFonts.urbanist(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ends the session and shows Sign in. The device is wiped even when the
/// backend cannot be reached, so the rider is always signed out here.
Future<void> signOutAndShowSignIn({
  AuthController? auth,
  NavigatorState? navigator,
}) async {
  try {
    await (auth ?? AppScope.instance.auth).signOut();
  } catch (error) {
    AppLog.warning(
      'auth.sign_out_remote_failed',
      extra: {'error': error.toString()},
    );
  }
  showSignInRoot(navigator: navigator);
}

/// Sign in as the root gate's child, every route above it closed.
void showSignInRoot({NavigatorState? navigator}) {
  showMoveraRoot(
    const SignIn(),
    navigator: navigator != null && navigator.mounted ? navigator : null,
  );
}
