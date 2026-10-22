import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/profile/presentation/language_picker.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/l10n/l10n.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key, this.controller, this.securityController});

  final ProfileController? controller;
  final AccountSecurityController? securityController;

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
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

  /// FLOW-15: a failed save used to escape the tap as an unhandled error.
  Future<void> _save(RiderProfileData next) async {
    try {
      await _profile.update(next);
    } catch (_) {
      if (mounted) {
        MoveraToast.show(context, context.l10n.saveFailed);
      }
    }
  }

  String _valueOrNotAdded(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? context.l10n.notAdded : trimmed;
  }

  String _serverContact(
    String value, {
    required bool verified,
    required String unavailableLabel,
  }) {
    if (!_security.available || _security.state == null) {
      return unavailableLabel;
    }
    if (value.trim().isEmpty) return context.l10n.notAdded;
    return verified ? context.l10n.valueVerified(value) : context.l10n.valueNotVerified(value);
  }

  @override
  Widget build(BuildContext context) {
    final ride = _profile.profile;
    final account = _security.state;
    final hasPhoto = ride.photoAsset.trim().isNotEmpty;

    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          AccountHeadline(
            context.l10n.accountPersonalInfo,
            body: context.l10n.personalInfoBody,
          ),
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColor.liteBlue,
              backgroundImage: hasPhoto ? AssetImage(ride.photoAsset) : null,
              child: hasPhoto
                  ? null
                  : const AppIconAsset(
                      AppAssets.solarUserRounded,
                      size: 40,
                      color: Color(0xFF2D5878),
                    ),
            ),
          ),
          const SizedBox(height: 22),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarUserId),
                title: context.l10n.name,
                body: _valueOrNotAdded(ride.name),
                onTap: () async {
                  final next = await showAccountTextEditor(
                    context,
                    title: context.l10n.name,
                    value: ride.name,
                    emptyError: context.l10n.enterYourName,
                    // rider-u78: the server refuses a longer name.
                    maxLength: RiderProfileData.maxNameLength,
                  );
                  if (next != null && next.isNotEmpty) {
                    // rider-r3-9: from the profile as it is now, not as it
                    // was at build time (a gender save may still be on its
                    // way and has not rebuilt this page yet).
                    await _save(_profile.profile.copyWith(name: next));
                  }
                },
              ),
              AccountTile(
                mark: AccountIcon.asset(
                  ride.gender == 'Woman'
                      ? AppAssets.solarWomen
                      : ride.gender == 'Man'
                      ? AppAssets.solarMen
                      : AppAssets.solarUserRounded,
                ),
                title: context.l10n.gender,
                body: _valueOrNotAdded(
                  ride.gender == 'Woman'
                      ? context.l10n.genderWoman
                      : ride.gender == 'Man'
                      ? context.l10n.genderMan
                      : '',
                ),
                onTap: () async {
                  final next = await showAccountChoice(
                    context,
                    title: context.l10n.gender,
                    options: const ['Woman', 'Man'],
                    selected: ride.gender,
                    labelOf: (g) => g == 'Woman'
                        ? context.l10n.genderWoman
                        : context.l10n.genderMan,
                  );
                  if (next != null) {
                    await _save(_profile.profile.copyWith(gender: next));
                  }
                },
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarPhone),
                title: context.l10n.phone,
                body: _serverContact(
                  account?.phone ?? '',
                  verified: account?.phoneVerified == true,
                  unavailableLabel: context.l10n.serverPhoneUnavailable,
                ),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarLetter),
                title: context.l10n.email,
                body: _serverContact(
                  account?.email ?? '',
                  verified: account?.emailVerified == true,
                  unavailableLabel: context.l10n.serverEmailStatusUnavailable,
                ),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarGlobal),
                title: context.l10n.language,
                body: AppScope.instance.language.language.label,
                showDivider: false,
                onTap: () async {
                  await pickAppLanguage(context, profile: _profile);
                  _refresh();
                },
              ),
            ],
          ),
          if (_security.loading && account == null) ...[
            const SizedBox(height: 14),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
