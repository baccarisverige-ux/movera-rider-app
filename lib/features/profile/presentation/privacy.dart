import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key, this.controller});

  final ProfileController? controller;

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  late final ProfileController _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.controller ?? AppScope.instance.profile;
    _profile.addListener(_refresh);
  }

  @override
  void dispose() {
    _profile.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// rider-u150: a save the server refused is undone and said so, instead
  /// of escaping the switch as an unhandled error. rider-u154: each switch
  /// changes the profile as it is now, not the copy this page was built
  /// from.
  Future<void> _save(RiderProfileData next) async {
    try {
      await _profile.update(next);
    } catch (_) {
      if (mounted) MoveraToast.show(context, context.l10n.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _profile.profile;
    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          AccountHeadline(
            context.l10n.accountPrivacy,
            body: context.l10n.privacyBody,
          ),
          const SizedBox(height: 18),
          AccountGroup(
            children: [
              AccountTile(
                mark: const AccountIcon(Icons.description_outlined),
                title: context.l10n.accountPrivacyNotice,
                body: context.l10n.privacyNoticeBody,
                showDivider: false,
                onTap: () {
                  Navigator.push(
                    context,
                    RightToLeftTransition(
                      const AccountLegalPage(kind: 'privacy'),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              context.l10n.howWeReachYou,
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
                mark: const AccountIcon(Icons.notifications_none_rounded),
                title: context.l10n.rideUpdates,
                body: context.l10n.rideUpdatesBody,
                trailing: Switch.adaptive(
                  value: ride.rideUpdates,
                  activeThumbColor: adaptiveSwitchThumbColor(
                    context,
                    kAccountAccent,
                  ),
                  activeTrackColor: adaptiveSwitchTrackColor(
                    context,
                    kAccountAccent,
                  ),
                  onChanged: (on) =>
                      _save(_profile.profile.copyWith(rideUpdates: on)),
                ),
              ),
              AccountTile(
                mark: const AccountIcon(Icons.mail_outline_rounded),
                title: context.l10n.email,
                body: context.l10n.emailBody,
                trailing: Switch.adaptive(
                  value: ride.emailUpdates,
                  activeThumbColor: adaptiveSwitchThumbColor(
                    context,
                    kAccountAccent,
                  ),
                  activeTrackColor: adaptiveSwitchTrackColor(
                    context,
                    kAccountAccent,
                  ),
                  onChanged: (on) =>
                      _save(_profile.profile.copyWith(emailUpdates: on)),
                ),
              ),
              AccountTile(
                mark: const AccountIcon(Icons.local_offer_outlined),
                title: context.l10n.offers,
                body: context.l10n.offersBody,
                showDivider: false,
                trailing: Switch.adaptive(
                  value: ride.promotions,
                  activeThumbColor: adaptiveSwitchThumbColor(
                    context,
                    kAccountAccent,
                  ),
                  activeTrackColor: adaptiveSwitchTrackColor(
                    context,
                    kAccountAccent,
                  ),
                  onChanged: (on) =>
                      _save(_profile.profile.copyWith(promotions: on)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text(
              context.l10n.appsWithAccess,
              style: accountText(
                13,
                weight: FontWeight.w600,
                color: kAccountMuted,
              ),
            ),
          ),
          MoveraEmptyState(
            icon: Icons.apps_outlined,
            title: context.l10n.noConnectedApps,
            message: context.l10n.noConnectedAppsBody,
            compact: true,
          ),
        ],
      ),
    );
  }
}
