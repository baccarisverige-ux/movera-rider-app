import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/domain/account_security.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key, this.securityController});

  final AccountSecurityController? securityController;

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  late final AccountSecurityController _security;

  @override
  void initState() {
    super.initState();
    _security = widget.securityController ?? AppScope.instance.accountSecurity;
    _security.addListener(_refresh);
    if (_security.state == null && !_security.loading) {
      unawaited(_security.load());
    }
  }

  @override
  void dispose() {
    _security.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _passwordLine(DateTime? when, bool supported) {
    if (!supported) return context.l10n.comingSoon;
    if (when == null) return context.l10n.notSet;
    return context.l10n.lastChanged(L10n.formatDate(when, 'yMd'));
  }

  @override
  Widget build(BuildContext context) {
    final security = _security.state;
    if (_security.loading && security == null) {
      return const AccountScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_security.available || security == null) {
      return AccountScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            AccountHeadline(
              context.l10n.accountSecurity,
              body: context.l10n.securityBody,
            ),
            const SizedBox(height: 18),
            AccountGroup(
              children: [
                AccountTile(
                  mark: const AccountIcon(Icons.shield_outlined),
                  title: context.l10n.securityUnavailable,
                  body: _security.errorMessage ??
                      context.l10n.securityUnavailableBody,
                  showDivider: false,
                  onTap: _security.loading
                      ? null
                      : () => unawaited(_security.load()),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final caps = security.capabilities;
    final hasOtherLogin = security.sessions.any((item) => !item.current);
    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          AccountHeadline(context.l10n.accountSecurity, body: context.l10n.securityBody),
          const SizedBox(height: 18),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon(Icons.key_outlined),
                title: context.l10n.passkeys,
                body: caps.passkeys
                    ? (security.passkeyEnabled
                        ? context.l10n.passkeyReady
                        : context.l10n.noPasskey)
                    : context.l10n.comingSoon,
              ),
              AccountTile(
                mark: const AccountIcon(Icons.password_outlined),
                title: context.l10n.password,
                body: _passwordLine(
                  security.passwordUpdatedAt,
                  caps.password,
                ),
              ),
              AccountTile(
                mark: const AccountIcon(Icons.phonelink_lock_outlined),
                title: context.l10n.authenticator,
                body: caps.authenticator
                    ? (security.authenticatorEnabled
                        ? context.l10n.otpOn
                        : context.l10n.notConfigured)
                    : context.l10n.comingSoon,
              ),
              AccountTile(
                mark: const AccountIcon(Icons.security_outlined),
                title: context.l10n.twoStep,
                body: caps.twoStep
                    ? (security.twoStepEnabled ? context.l10n.on : context.l10n.off)
                    : context.l10n.comingSoon,
              ),
              AccountTile(
                mark: const AccountIcon(Icons.phone_iphone_outlined),
                title: context.l10n.recoveryPhone,
                body: caps.recoveryPhone
                    ? (security.recoveryPhone ?? context.l10n.notConfigured)
                    : context.l10n.comingSoon,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              context.l10n.connectedAccounts,
              style: accountText(
                13,
                weight: FontWeight.w600,
                color: kAccountMuted,
              ),
            ),
          ),
          AccountGroup(
            children: [
              AccountTile(
                mark: Image.asset(AppAssets.google, height: 20),
                title: 'Google',
                body: caps.connectedAccounts
                    ? (security.googleConnected ? context.l10n.connected : context.l10n.notConnected)
                    : context.l10n.comingSoon,
              ),
              AccountTile(
                mark: Image.asset(AppAssets.apple, height: 20),
                title: 'Apple',
                body: caps.connectedAccounts
                    ? (security.appleConnected ? context.l10n.connected : context.l10n.notConnected)
                    : context.l10n.comingSoon,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              context.l10n.loginActivity,
              style: accountText(
                13,
                weight: FontWeight.w600,
                color: kAccountMuted,
              ),
            ),
          ),
          AccountGroup(
            children: security.sessions.isEmpty
                ? [
                    AccountTile(
                      mark: AccountIcon(Icons.devices_outlined),
                      title: context.l10n.noSignInActivity,
                      body: context.l10n.noSessionRecords,
                      showDivider: false,
                    ),
                  ]
                : [
                    for (var i = 0; i < security.sessions.length; i++)
                      _LoginTile(
                        session: security.sessions[i],
                        showDivider: i != security.sessions.length - 1,
                      ),
                  ],
          ),
          if (hasOtherLogin) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AccountTile(
                title: context.l10n.signOutOtherDevices,
                body: !caps.signOutOtherDevices
                    ? context.l10n.comingSoon
                    : !caps.reauthentication
                        ? context.l10n.comingSoon
                        : !security.hasFreshReauthentication
                            ? context.l10n.reauthBeforeRevoke
                            : context.l10n.serverRevokesOthers,
                showDivider: false,
                onTap: caps.signOutOtherDevices &&
                        caps.reauthentication &&
                        security.hasFreshReauthentication &&
                        !_security.loading
                    ? () async {
                        final signOutOthers = context.l10n.signOutOthers;
                        final confirm = await showAccountChoice(
                          context,
                          title: context.l10n.signOutOtherDevicesQ,
                          options: [signOutOthers, context.l10n.cancel],
                          selected: '',
                        );
                        if (confirm != signOutOthers) return;
                        await _security.signOutOtherDevices();
                      }
                    : null,
              ),
            ),
          ],
          if (_security.errorMessage != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _security.errorMessage!,
                style: accountText(13, color: const Color(0xFFB42318)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoginTile extends StatelessWidget {
  const _LoginTile({required this.session, required this.showDivider});

  final AccountSession session;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AccountTile(
      mark: const AccountIcon(Icons.smartphone_outlined),
      title: session.device,
      body: session.current
          ? context.l10n.thisSession(session.place)
          : '${session.place}  ·  ${session.source}',
      showDivider: showDivider,
    );
  }
}
