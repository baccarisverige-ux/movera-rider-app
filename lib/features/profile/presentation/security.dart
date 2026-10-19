import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/domain/account_security.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';

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
    if (!supported) return 'Coming soon';
    if (when == null) return 'Not set';
    return 'Last changed ${when.day}/${when.month}/${when.year}';
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
            const AccountHeadline(
              'Security',
              body: 'How you sign in to Movera.',
            ),
            const SizedBox(height: 18),
            AccountGroup(
              children: [
                AccountTile(
                  mark: const AccountIcon(Icons.shield_outlined),
                  title: 'Security controls unavailable',
                  body: _security.errorMessage ??
                      'Movera could not verify account security with the server.',
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
          const AccountHeadline('Security', body: 'How you sign in to Movera.'),
          const SizedBox(height: 18),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon(Icons.key_outlined),
                title: 'Passkeys',
                body: caps.passkeys
                    ? (security.passkeyEnabled
                        ? 'Ready on this device'
                        : 'No passkey configured')
                    : 'Coming soon',
              ),
              AccountTile(
                mark: const AccountIcon(Icons.password_outlined),
                title: 'Password',
                body: _passwordLine(
                  security.passwordUpdatedAt,
                  caps.password,
                ),
              ),
              AccountTile(
                mark: const AccountIcon(Icons.phonelink_lock_outlined),
                title: 'Authenticator',
                body: caps.authenticator
                    ? (security.authenticatorEnabled
                        ? 'One-time codes are on'
                        : 'Not configured')
                    : 'Coming soon',
              ),
              AccountTile(
                mark: const AccountIcon(Icons.security_outlined),
                title: '2-step verification',
                body: caps.twoStep
                    ? (security.twoStepEnabled ? 'On' : 'Off')
                    : 'Coming soon',
              ),
              AccountTile(
                mark: const AccountIcon(Icons.phone_iphone_outlined),
                title: 'Recovery phone',
                body: caps.recoveryPhone
                    ? (security.recoveryPhone ?? 'Not configured')
                    : 'Coming soon',
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              'Connected accounts',
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
                    ? (security.googleConnected ? 'Connected' : 'Not connected')
                    : 'Coming soon',
              ),
              AccountTile(
                mark: Image.asset(AppAssets.apple, height: 20),
                title: 'Apple',
                body: caps.connectedAccounts
                    ? (security.appleConnected ? 'Connected' : 'Not connected')
                    : 'Coming soon',
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              'Login activity',
              style: accountText(
                13,
                weight: FontWeight.w600,
                color: kAccountMuted,
              ),
            ),
          ),
          AccountGroup(
            children: security.sessions.isEmpty
                ? const [
                    AccountTile(
                      mark: AccountIcon(Icons.devices_outlined),
                      title: 'No sign-in activity to show',
                      body: 'Movera has no session records to show.',
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
                title: 'Sign out other devices',
                body: !caps.signOutOtherDevices
                    ? 'Coming soon'
                    : !caps.reauthentication
                        ? 'Coming soon'
                        : !security.hasFreshReauthentication
                            ? 'Reauthenticate before revoking other sessions'
                            : 'Server will revoke every session except this one.',
                showDivider: false,
                onTap: caps.signOutOtherDevices &&
                        caps.reauthentication &&
                        security.hasFreshReauthentication &&
                        !_security.loading
                    ? () async {
                        final confirm = await showAccountChoice(
                          context,
                          title: 'Sign out other devices?',
                          options: const ['Sign out others', 'Cancel'],
                          selected: '',
                        );
                        if (confirm != 'Sign out others') return;
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
          ? 'This session  ·  ${session.place}'
          : '${session.place}  ·  ${session.source}',
      showDivider: showDivider,
    );
  }
}
