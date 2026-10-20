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
import 'package:movera_rider/shared/design_system/movera_toast.dart';

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
        MoveraToast.show(context, 'Couldn’t save that change. Try again.');
      }
    }
  }

  String _valueOrNotAdded(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Not added' : trimmed;
  }

  String _serverContact(
    String value, {
    required bool verified,
    required String unavailableLabel,
  }) {
    if (!_security.available || _security.state == null) {
      return unavailableLabel;
    }
    if (value.trim().isEmpty) return 'Not added';
    return verified ? '$value · Verified' : '$value · Not verified';
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
          const AccountHeadline(
            'Personal info',
            body: 'Name, phone, and how we reach you.',
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
                title: 'Name',
                body: _valueOrNotAdded(ride.name),
                onTap: () async {
                  final next = await showAccountTextEditor(
                    context,
                    title: 'Name',
                    value: ride.name,
                    emptyError: 'Enter your name',
                  );
                  if (next != null && next.isNotEmpty) {
                    await _save(ride.copyWith(name: next));
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
                title: 'Gender',
                body: _valueOrNotAdded(
                  ride.gender == 'Woman' || ride.gender == 'Man'
                      ? ride.gender
                      : '',
                ),
                onTap: () async {
                  final next = await showAccountChoice(
                    context,
                    title: 'Gender',
                    options: const ['Woman', 'Man'],
                    selected: ride.gender,
                  );
                  if (next != null) {
                    await _save(ride.copyWith(gender: next));
                  }
                },
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarPhone),
                title: 'Phone',
                body: _serverContact(
                  account?.phone ?? '',
                  verified: account?.phoneVerified == true,
                  unavailableLabel: 'Server phone status unavailable',
                ),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarLetter),
                title: 'Email',
                body: _serverContact(
                  account?.email ?? '',
                  verified: account?.emailVerified == true,
                  unavailableLabel: 'Server email status unavailable',
                ),
              ),
              AccountTile(
                mark: const AccountIcon.asset(AppAssets.solarGlobal),
                title: 'Language',
                body: ride.language,
                showDivider: false,
                onTap: () async {
                  final next = await showAccountChoice(
                    context,
                    title: 'Language',
                    options: const ['English', 'Svenska'],
                    selected: ride.language,
                  );
                  if (next != null) {
                    await _save(ride.copyWith(language: next));
                  }
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
