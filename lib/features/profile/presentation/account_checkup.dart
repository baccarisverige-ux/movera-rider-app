import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class AccountCheckupPage extends StatefulWidget {
  const AccountCheckupPage({
    super.key,
    this.controller,
    this.securityController,
  });

  final ProfileController? controller;
  final AccountSecurityController? securityController;

  @override
  State<AccountCheckupPage> createState() => _AccountCheckupPageState();
}

class _AccountCheckupPageState extends State<AccountCheckupPage> {
  late final ProfileController _profile;
  late final AccountSecurityController _security;

  @override
  void initState() {
    super.initState();
    _profile = widget.controller ?? AppScope.instance.profile;
    _security = widget.securityController ?? AppScope.instance.accountSecurity;
    _profile.addListener(_refresh);
    _security.addListener(_refresh);
    if (_security.state == null && !_security.loading) {
      unawaited(_security.load());
    }
  }

  @override
  void dispose() {
    _profile.removeListener(_refresh);
    _security.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final security = _security.available ? _security.state : null;
    final phoneVerified = security?.phoneVerified == true;
    final twoStepEnabled = security?.twoStepEnabled == true;
    final recoveryPhone = security?.recoveryPhone;
    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          AccountHeadline(
            context.l10n.accountCheck,
            body: context.l10n.accountCheckBody,
          ),
          const SizedBox(height: 18),
          if (_security.loading && security == null)
            const Center(child: CircularProgressIndicator())
          else
            AccountGroup(
              children: [
                AccountTile(
                  mark: const AccountIcon(Icons.phone_outlined),
                  title: context.l10n.phoneNumber,
                  body: security == null
                      ? context.l10n.verificationUnavailable
                      : security.phone.isEmpty
                          ? context.l10n.noPhoneAdded
                          : phoneVerified
                              ? context.l10n.valueVerified(security.phone)
                              : context.l10n.valueNotVerified(security.phone),
                  trailing: Icon(
                    phoneVerified
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: phoneVerified ? kAccountAccent : kAccountMuted,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      RightToLeftTransition(
                        PersonalInfoPage(
                          controller: _profile,
                          securityController: _security,
                        ),
                      ),
                    );
                  },
                ),
                AccountTile(
                  mark: const AccountIcon(Icons.security_outlined),
                  title: context.l10n.twoStep,
                  body: security == null
                      ? context.l10n.securityStatusUnavailable
                      : security.capabilities.twoStep
                          ? (twoStepEnabled ? context.l10n.on : context.l10n.off)
                          : context.l10n.unavailable,
                  trailing: Icon(
                    twoStepEnabled
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: twoStepEnabled ? kAccountAccent : kAccountMuted,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      RightToLeftTransition(
                        SecurityPage(securityController: _security),
                      ),
                    );
                  },
                ),
                AccountTile(
                  mark: const AccountIcon(Icons.phone_iphone_outlined),
                  title: context.l10n.recoveryPhone,
                  body: security == null
                      ? context.l10n.recoveryStatusUnavailable
                      : security.capabilities.recoveryPhone
                          ? (recoveryPhone ?? context.l10n.notConfigured)
                          : context.l10n.unavailable,
                  showDivider: false,
                  trailing: Icon(
                    recoveryPhone?.isNotEmpty == true
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: recoveryPhone?.isNotEmpty == true
                        ? kAccountAccent
                        : kAccountMuted,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      RightToLeftTransition(
                        SecurityPage(securityController: _security),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
