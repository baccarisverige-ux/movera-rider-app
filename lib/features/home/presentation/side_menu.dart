import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/auth/presentation/sign_out_flow.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:movera_rider/features/profile/presentation/refer_and_earn.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// The rider's menu as a full-screen page: name and photo, Wallet, four
/// picture tiles, six illustrated cards, then the account rows.
/// Illustrations: unDraw (see assets/images/menu/README.md).
class RiderMenuPage extends StatelessWidget {
  const RiderMenuPage({super.key, this.onStartBooking, this.onSchedule});

  /// Called when the rider wants to book from here (the Where to card, or
  /// Ride History's empty-state "Book a ride"): the menu leaves first and
  /// Home opens Where to.
  final VoidCallback? onStartBooking;

  /// Called from the Later chip: the menu leaves and Home opens Book for
  /// later.
  final VoidCallback? onSchedule;

  static Future<void> open(
    BuildContext context, {
    VoidCallback? onStartBooking,
    VoidCallback? onSchedule,
  }) {
    return Navigator.of(context).push(
      RightToLeftTransition(
        RiderMenuPage(onStartBooking: onStartBooking, onSchedule: onSchedule),
      ),
    );
  }

  static const String appVersion = '1.0.0';

  static const Color _ink = MoveraTokens.ink;
  // UI-6: was 0xFF6B757D, 4.27:1 on the card fill 0xFFF3F4F5.
  static const Color _muted = MoveraTokens.subtleOnFill;
  static const Color _card = Color(0xFFF3F4F5);
  static const Color _avatarTint = Color(0xFFE6EAEE);
  static const Color _badge = Color(0xFFE8333B);
  static const Color _line = MoveraTokens.line;

  static const String _art = 'assets/images/menu';

  Future<void> _pushPage(BuildContext context, Widget page) async {
    final nav = Navigator.of(context);
    final result = await nav.push<Object?>(RightToLeftTransition(page));
    if (!nav.mounted) return;
    // FLOW-17: name, wallet balance and promotion may have changed there.
    if (context.mounted) _MenuRefresh.refresh(context);
    // D-026: Ride History's "Book a ride" goes to booking, not back here.
    if (result == RideHistory.startBookingResult) {
      nav.pop();
      onStartBooking?.call();
    }
  }

  @override
  Widget build(BuildContext context) => _MenuRefresh(builder: _buildMenu);

  Widget _buildMenu(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(context),
              const SizedBox(height: 2),
              _profileHeader(),
              const SizedBox(height: 16),
              _whereTo(context),
              const SizedBox(height: 10),
              _walletCard(context),
              const SizedBox(height: 10),
              _tiles(context),
              const SizedBox(height: 10),
              ..._featureCards(context),
              const SizedBox(height: 18),
              ..._accountRows(context),
              const SizedBox(height: 22),
              Text(
                'Movera Rider v$appVersion',
                style: _text(13, color: MoveraTokens.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  Widget _topBar(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Back',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            // UI-4: 44 x 44 (was 40 x 40); the gap below is 4 px shorter.
            child: const SizedBox(
              key: ValueKey('menu-back'),
              width: A11y.minTapIOS,
              height: A11y.minTapIOS,
              child: Center(
                child: AppIconAsset(
                  AppAssets.solarArrowLeft,
                  size: 24,
                  color: _ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The rider's name, large, with the photo on the right.
  Widget _profileHeader() {
    final controller = AppScope.instance.profile;
    final profile = controller.profile;
    final hasPhoto = profile.photoAsset.trim().isNotEmpty;
    final first = profile.name.trim().split(RegExp(r'\s+')).first;
    final greeting = first.isEmpty ? controller.displayName() : 'Hi $first';

    return Row(
      children: [
        Expanded(
          child: Text(
            greeting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _text(
              26,
              weight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(width: 16),
        ClipOval(
          child: SizedBox(
            width: 60,
            height: 60,
            child: hasPhoto
                ? Image.asset(
                    excludeFromSemantics: true,
                    profile.photoAsset,
                    fit: BoxFit.cover,
                  )
                : const ColoredBox(
                    color: _avatarTint,
                    child: Center(
                      child: AppIconAsset(
                        AppAssets.solarUserRounded,
                        size: 30,
                        color: _muted,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The Where to card: the search box (with the Later chip) and a picture.
  /// Both leave the menu and continue on Home, like the Home sheet.
  Widget _whereTo(BuildContext context) {
    void go(VoidCallback? action) {
      Navigator.of(context).pop();
      action?.call();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Where to?',
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => go(onStartBooking),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _line),
                    ),
                    // UI-10: the Later chip may take what the label leaves
                    // free, so large text shrinks it instead of overflowing.
                    child: LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          const AppIconAsset(
                            AppAssets.solarSearch,
                            size: 22,
                            color: _ink,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Where to?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(16, color: _muted),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.max(48.0, box.maxWidth - 88),
                            ),
                            // UI-4: the chip stays 29 px tall; its target
                            // is 44 px, the height of the search box.
                            child: MoveraHitArea(
                              label: 'Later',
                              onTap: () => go(onSchedule),
                              minWidth: 0,
                              child: Material(
                                color: _card,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => go(onSchedule),
                                  excludeFromSemantics: true,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Later',
                                        maxLines: 1,
                                        style: _text(
                                          12,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _picture('navigation', width: 72, height: 56),
        ],
      ),
    );
  }

  Widget _picture(
    String name, {
    required double width,
    required double height,
  }) {
    // The box is fixed so a wide drawing never pushes the label aside.
    return SizedBox(
      width: width,
      height: height,
      child: SvgPicture.asset(
        '$_art/$name.svg',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }

  Widget _tap({
    required String label,
    required VoidCallback onTap,
    required Widget child,
    double radius = 16,
  }) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: _card,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: _ink.withValues(alpha: 0.05),
            highlightColor: _ink.withValues(alpha: 0.04),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Wallet with the balance under its title and the wallet picture.
  Widget _walletCard(BuildContext context) {
    return _WalletBalance(
      builder: (context, balance, reload) =>
          _walletTile(context, balance, reload),
    );
  }

  Widget _walletTile(
    BuildContext context,
    double? balance,
    VoidCallback reload,
  ) {
    final amount = balance == null ? null : formatKr(balance);
    return _tap(
      // UI-7: the balance is part of what a screen reader hears.
      label: amount == null ? 'Wallet' : 'Wallet, $amount',
      onTap: () async {
        await _pushPage(context, const WalletAndPaymentsScreen());
        // A top-up in Wallet shows here on the way back.
        reload();
      },
      // UI-10: a minimum height, so large text grows the card.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 80),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet', style: _text(18, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    if (amount == null)
                      const SizedBox(height: 18)
                    else
                      Text(
                        amount,
                        maxLines: 1,
                        style: _text(14, color: _muted),
                      ),
                  ],
                ),
              ),
              _picture('wallet', width: 72, height: 56),
            ],
          ),
        ),
      ),
    );
  }

  /// Two columns of picture tiles.
  Widget _tiles(BuildContext context) {
    final items = <(String, String, VoidCallback)>[
      ('Ride History', 'order_ride', () => _pushPage(context, RideHistory())),
      (
        'Notifications',
        'notify',
        () => _pushPage(context, const NotificationScreen()),
      ),
      (
        'Saved Places',
        'current_location',
        () => _pushPage(context, SavedPlaces()),
      ),
      ('Support', 'questions', () => _pushPage(context, const SupportHome())),
    ];
    Widget tile((String, String, VoidCallback) item) {
      return _tap(
        label: item.$1,
        onTap: item.$3,
        child: SizedBox(
          height: 76,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.$1,
                      maxLines: 1,
                      style: _text(14.5, weight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _picture(item.$2, width: 56, height: 46),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: tile(items[0])),
            const SizedBox(width: 10),
            Expanded(child: tile(items[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: tile(items[2])),
            const SizedBox(width: 10),
            Expanded(child: tile(items[3])),
          ],
        ),
      ],
    );
  }

  /// The six illustrated cards.
  List<Widget> _featureCards(BuildContext context) {
    final promotion = AppScope.instance.promotion.active;
    final promoBody = promotion == null
        ? 'Offers you can use are applied automatically to your ride.'
        : '${promotion.percentOff}% off your next ${promotion.ridesTotal} rides'
              ' · ${promotion.ridesLeft} left. We apply the offer that saves you'
              ' the most.';
    final cards = <_FeatureCard>[
      _FeatureCard(
        title: 'Your promotions',
        body: promoBody,
        picture: 'discount',
        isNew: promotion != null,
        onTap: () {
          if (promotion != null) {
            PromotionDetailsSheet.open(context, promotion);
          } else {
            _pushPage(context, const WalletAndPaymentsScreen());
          }
        },
      ),
      _FeatureCard(
        title: 'Safety checkup',
        body: 'Add a trusted contact and set your safety preferences.',
        picture: 'protection_enabled',
        pictureWidth: 84,
        onTap: () => _pushPage(context, const SafetyHub()),
      ),
      _FeatureCard(
        title: 'Movera Family',
        body: 'Coming soon: book and follow rides for your family.',
        picture: 'family',
        onTap: () => _pushPage(
          context,
          const HelpArticle(
            title: 'Movera Family',
            body:
                'Soon you will be able to add family members to your account and book rides for them, with the trip and the driver visible to you from start to finish. We will let you know the moment it is ready.',
          ),
        ),
      ),
      _FeatureCard(
        title: 'Invite friends',
        // FLOW-16: no reward exists yet, so the card promises none.
        body: 'Coming soon: invite friends to Movera.',
        picture: 'referral',
        onTap: () => _pushPage(context, const ReferAndEarn()),
      ),
      _FeatureCard(
        title: 'Movera Business',
        body: 'Coming soon: keep work rides and receipts separate.',
        picture: 'travel_mode',
        pictureWidth: 96,
        onTap: () => _pushPage(
          context,
          const HelpArticle(
            title: 'Movera Business',
            body:
                'A business profile keeps your work rides apart from your personal ones, with monthly receipts ready for expensing. It is on its way; we will let you know when it opens.',
          ),
        ),
      ),
      _FeatureCard(
        title: 'Greener rides',
        body: 'Choose Electric for fossil-free rides.',
        picture: 'nature',
        onTap: () => _pushPage(
          context,
          const HelpArticle(
            title: 'Greener rides',
            body:
                'Choose the Electric category to ride emission-free. Soon your receipts will show the CO₂ you saved on every trip and over the year.',
          ),
        ),
      ),
    ];
    return [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _featureCard(cards[i]),
      ],
    ];
  }

  Widget _featureCard(_FeatureCard card) {
    return _tap(
      label: card.title,
      onTap: card.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(17, weight: FontWeight.w600),
                        ),
                      ),
                      if (card.isNew) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _badge,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'NEW',
                            style: _text(
                              11,
                              weight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _text(14, color: _muted, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _picture(card.picture, width: card.pictureWidth, height: 82),
          ],
        ),
      ),
    );
  }

  /// Account rows: every one opens a screen that already exists.
  List<Widget> _accountRows(BuildContext context) {
    final profile = AppScope.instance.profile;
    final security = AppScope.instance.accountSecurity;
    final rows = <(String, String, String, VoidCallback)>[
      (
        AppAssets.solarUserRounded,
        'Personal info',
        'Name, phone, email, language',
        () => _pushPage(
          context,
          PersonalInfoPage(controller: profile, securityController: security),
        ),
      ),
      (
        AppAssets.solarShieldCheck,
        'Security',
        'Passkeys, 2-step, devices',
        () => _pushPage(context, SecurityPage(securityController: security)),
      ),
      (
        AppAssets.solarLock,
        'Privacy',
        'How Movera uses your data',
        () => _pushPage(context, PrivacyPage(controller: profile)),
      ),
      (
        AppAssets.solarDocument,
        'Terms',
        'How Movera rides work',
        () => _pushPage(context, const AccountLegalPage(kind: 'terms')),
      ),
      (
        AppAssets.solarInfoCircle,
        'Privacy notice',
        'What we keep and why',
        () => _pushPage(context, const AccountLegalPage(kind: 'privacy')),
      ),
      (
        AppAssets.solarBuildings,
        'About Movera',
        'Company information',
        () => _pushPage(
          context,
          const HelpArticle(
            title: 'About Movera',
            body:
                'Movera is a ride app for Sweden. Available booking and payment options are shown during your ride request.\n\nIcons: Solar Icons by 480 Design (CC BY 4.0). Illustrations: unDraw.',
          ),
        ),
      ),
      (
        AppAssets.solarArrowLeft,
        'Sign out',
        'Remove your data from this device',
        () => unawaited(confirmAndSignOut(context)),
      ),
    ];
    return [for (final row in rows) _accountRow(row)];
  }

  Widget _accountRow((String, String, String, VoidCallback) row) {
    return Semantics(
      button: true,
      label: row.$2,
      onTap: row.$4,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: row.$4,
            borderRadius: BorderRadius.circular(12),
            splashColor: _ink.withValues(alpha: 0.05),
            highlightColor: _ink.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              child: Row(
                children: [
                  AppIconAsset(row.$1, size: 26, color: _ink),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(17, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          row.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(13.5, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard {
  const _FeatureCard({
    required this.title,
    required this.body,
    required this.picture,
    required this.onTap,
    this.isNew = false,
    this.pictureWidth = 100,
  });

  final String title;
  final String body;
  final String picture;
  final VoidCallback onTap;
  final bool isNew;
  final double pictureWidth;
}

/// Rebuilds the menu when the rider's profile or promotion changes, and
/// after any page opened from it closes (FLOW-17): the header, the wallet
/// balance and the promotion card used to keep what they first read.
class _MenuRefresh extends StatefulWidget {
  const _MenuRefresh({required this.builder});

  final WidgetBuilder builder;

  static void refresh(BuildContext context) =>
      context.findAncestorStateOfType<_MenuRefreshState>()?.refresh();

  @override
  State<_MenuRefresh> createState() => _MenuRefreshState();
}

class _MenuRefreshState extends State<_MenuRefresh> {
  late final Listenable _sources = Listenable.merge([
    AppScope.instance.profile,
    AppScope.instance.promotion,
  ]);

  @override
  void initState() {
    super.initState();
    _sources.addListener(refresh);
  }

  @override
  void dispose() {
    _sources.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Builder(builder: widget.builder);
}

/// UI-14: loads the wallet balance once per menu, not on every rebuild, and
/// again only when asked (back from Wallet).
class _WalletBalance extends StatefulWidget {
  const _WalletBalance({required this.builder});

  final Widget Function(
    BuildContext context,
    double? balance,
    VoidCallback reload,
  )
  builder;

  @override
  State<_WalletBalance> createState() => _WalletBalanceState();
}

class _WalletBalanceState extends State<_WalletBalance> {
  late Future<double> _balance = _load();

  Future<double> _load() => AppScope.instance.walletController.loadBalance();

  void _reload() {
    if (!mounted) return;
    // UI-12: the callback must not return the Future (setState asserts).
    final next = _load();
    setState(() {
      _balance = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _balance,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data, _reload),
    );
  }
}
