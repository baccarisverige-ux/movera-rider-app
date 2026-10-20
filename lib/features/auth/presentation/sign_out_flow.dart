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
  final navigator = Navigator.of(context, rootNavigator: true);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        context.l10n.signOutQ,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: Text(
        context.l10n.signOutQBody,
        style: GoogleFonts.poppins(fontSize: 13.5),
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
  if (confirmed != true) return;
  await signOutAndShowSignIn(auth: auth, navigator: navigator);
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
