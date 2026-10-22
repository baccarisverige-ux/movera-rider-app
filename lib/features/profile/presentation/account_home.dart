import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/auth/presentation/sign_out_flow.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/presentation/account_checkup.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/profile/presentation/delete_account.dart';
import 'package:movera_rider/features/profile/presentation/language_picker.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class AccountHomePage extends StatefulWidget {
  const AccountHomePage({
    super.key,
    this.controller,
    this.securityController,
    this.language,
  });

  final ProfileController? controller;
  final AccountSecurityController? securityController;

  /// The app language (Q48); the app's own when null.
  final AppLanguageController? language;

  @override
  State<AccountHomePage> createState() => _AccountHomePageState();
}

class _AccountHomePageState extends State<AccountHomePage> {
  late final ProfileController _profile;
  late final AccountSecurityController _security;
  late final AppLanguageController _language;

  @override
  void initState() {
    super.initState();
    _profile = widget.controller ?? AppScope.instance.profile;
    _security = widget.securityController ?? AppScope.instance.accountSecurity;
    _language = widget.language ?? AppScope.instance.language;
    _language.addListener(_refresh);
    _profile.addListener(_refresh);
    _security.addListener(_refresh);
    if (_security.state == null && !_security.loading) {
      unawaited(_security.load());
    }
  }

  @override
  void dispose() {
    _language.removeListener(_refresh);
    _profile.removeListener(_refresh);
    _security.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// rider-u125: [name] lets pushPageOnce see the page is already open.
  Future<void> _open(Widget page, {String? name}) {
    return Navigator.push(
      context,
      RightToLeftTransition(page, settings: RouteSettings(name: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = _profile.profile;
    // D-024: invite the rider to fill it in rather than a placeholder.
    final name = ride.name.trim().isEmpty ? context.l10n.accountAddYourName : ride.name;
    final hasPhoto = ride.photoAsset.trim().isNotEmpty;
    final security = _security.available ? _security.state : null;
    final email = security == null
        ? context.l10n.serverEmailUnavailable
        : security.email.trim().isEmpty
        ? context.l10n.emailNotAdded
        : security.emailVerified
        ? context.l10n.valueVerified(security.email)
        : context.l10n.valueNotVerified(security.email);
    final checkupComplete = security?.checkupComplete == true;

    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: AccountHeadline(
              context.l10n.navAccount,
              body: context.l10n.accountHeadlineBody,
            ),
          ),
          AccountGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColor.liteBlue,
                      backgroundImage: hasPhoto
                          ? AssetImage(ride.photoAsset)
                          : null,
                      child: hasPhoto
                          ? null
                          : const AppIconAsset(
                              AppAssets.solarUserRounded,
                              size: 26,
                              color: Color(0xFF2D5878),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: accountText(18, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            style: accountText(13, color: kAccountMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarUserRounded),
                title: context.l10n.accountPersonalInfo,
                body: context.l10n.accountPersonalInfoBody,
                onTap: () => _open(
                  PersonalInfoPage(
                    controller: _profile,
                    securityController: _security,
                  ),
                ),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarShieldCheck),
                title: context.l10n.accountSecurity,
                body: context.l10n.accountSecurityBody,
                onTap: () => _open(SecurityPage(securityController: _security)),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarLock),
                title: context.l10n.accountPrivacy,
                body: context.l10n.accountPrivacyBody,
                onTap: () => _open(PrivacyPage(controller: _profile)),
              ),
              // Q48: "FR · Français"; the choice wins over the zone default.
              AccountTile(
                key: const ValueKey('account-language'),
                mark: const AccountIcon.asset(AppAssets.solarGlobal),
                title: context.l10n.language,
                body: _language.language.label,
                showDivider: false,
                onTap: () => pickAppLanguage(
                  context,
                  language: _language,
                  profile: _profile,
                ),
              ),
            ],
          ),
          if (!checkupComplete) ...[
            const SizedBox(height: 14),
            AccountGroup(
              children: [
                AccountTile(
                  mark: const AccountIcon.asset(AppAssets.solarCheckCircle),
                  title: context.l10n.accountFinish,
                  body: security == null
                      ? context.l10n.securityStatusUnavailableDot
                      : context.l10n.accountFinishBody,
                  showDivider: false,
                  onTap: () => _open(
                    AccountCheckupPage(
                      controller: _profile,
                      securityController: _security,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarShieldStar),
                title: context.l10n.accountSafety,
                body: context.l10n.accountSafetyBody,
                onTap: () => _open(const SafetyHub(), name: AppRoutes.safety),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarHeadphones),
                title: context.l10n.menuSupport,
                body: context.l10n.accountSupportBody,
                onTap: () => _open(const SupportHome()),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarDocument),
                title: context.l10n.accountTerms,
                body: context.l10n.accountTermsBody,
                onTap: () => _open(const AccountLegalPage(kind: 'terms')),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarInfoCircle),
                title: context.l10n.accountPrivacyNotice,
                body: context.l10n.accountPrivacyNoticeBody,
                showDivider: false,
                onTap: () => _open(const AccountLegalPage(kind: 'privacy')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarArrowLeft),
                title: context.l10n.accountSignOut,
                body: context.l10n.accountSignOutBody,
                onTap: () => unawaited(confirmAndSignOut(context)),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarUser),
                title: context.l10n.accountDelete,
                body: context.l10n.accountDeleteBody,
                danger: true,
                showDivider: false,
                onTap: () => _open(const DeleteAccountPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
