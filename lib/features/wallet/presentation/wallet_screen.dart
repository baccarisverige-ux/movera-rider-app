part of 'wallet.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.embedded = false,
    this.refreshToken = 0,
    this.flags = FeatureFlags.current,
    this.wallet,
  });

  final bool embedded;

  /// The wallet to read and save payment settings with; the app's without.
  final WalletController? wallet;

  /// A new value re-reads the wallet balance (FLOW-17).
  final int refreshToken;
  final FeatureFlags flags;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

/// How the Payments tab shows a contract payment method (v0.18.10, owner
/// G8 item 2).
enum WalletMethodState { hidden, comingSoon, available }

/// [method] on the Payments tab: hidden when the zone or the server does
/// not offer it, coming soon (greyed, never the default) when the server
/// does not take it yet. Without [options] (an older server) every zone
/// method is available, as before.
WalletMethodState walletMethodState(
  String method,
  List<String> zoneMethods,
  Map<String, String>? options,
) {
  if (!zoneMethods.contains(method)) return WalletMethodState.hidden;
  if (options == null) return WalletMethodState.available;
  return switch (options[method]) {
    'available' => WalletMethodState.available,
    'coming_soon' => WalletMethodState.comingSoon,
    _ => WalletMethodState.hidden,
  };
}

class _WalletScreenState extends State<WalletScreen> {
  static const Color _ink = Color(0xFF171C1F);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _surface = Color(0xFFF4F5F4);
  static const Color _line = Color(0xFFE6E8E7);
  static const Color _accent = Color(0xFF356879);
  late final WalletController _homeWallet =
      widget.wallet ?? AppScope.instance.walletController;
  final SavedCardsController _cards = AppScope.instance.savedCards;

  /// Q7/Q8: the rider's current zone decides which wallet balance and
  /// which payment methods (its config's) are listed.
  String _currency = Money.defaultCurrency;
  List<String> _zoneMethods = ZoneDefaults.paymentMethods;
  WalletController get _wallet => _homeWallet.forCurrency(_currency);

  /// v0.18.10 `paymentOptions` (owner G8 item 2): null from an older
  /// server.
  Map<String, String>? _paymentOptions;
  bool _offers(String method) =>
      walletMethodState(method, _zoneMethods, _paymentOptions) !=
      WalletMethodState.hidden;

  /// On in admin but not taken by the server yet: shown "Kommer snart",
  /// never the default.
  bool _soon(String method) =>
      walletMethodState(method, _zoneMethods, _paymentOptions) ==
      WalletMethodState.comingSoon;

  Future<void> _loadZone() async {
    final zone = await currentRiderZone();
    List<String>? methods;
    Map<String, String>? options;
    try {
      final config = await AppScope.instance.riderConfig.forZone(zone.id);
      methods = config.paymentMethods;
      options = config.paymentOptions;
    } catch (_) {
      methods = null;
    }
    if (!mounted) return;
    setState(() {
      _currency = zone.currency;
      if (methods != null) _zoneMethods = methods;
      _paymentOptions = options;
    });
    await _reloadBalance();
  }

  bool _businessProfile = false;
  String _selectedMethod = 'cash';
  double _balance = 0;

  /// rider-fixrev3-5: bumped by every method or profile choice made on
  /// this screen, so a settings load that answers after a tap (the server
  /// default can take seconds in release) does not put the older value back.
  int _methodEdits = 0;
  int _profileEdits = 0;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  List<Map<String, String>> _extraMethods = [];

  @override
  void initState() {
    super.initState();
    _cards.addListener(_cardsChanged);
    _restorePaymentSettings();
    _loadCards();
    _loadZone();
  }

  @override
  void didUpdateWidget(covariant WalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reloadBalance();
  }

  Future<void> _reloadBalance() async {
    final currency = _currency;
    final balance = await _wallet.loadBalance();
    if (mounted && currency == _currency) setState(() => _balance = balance);
  }

  @override
  void dispose() {
    _cards.removeListener(_cardsChanged);
    super.dispose();
  }

  void _cardsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCards() async {
    try {
      await _cards.load();
    } catch (error) {
      AppLog.warning('wallet.cards_load_failed', extra: {'error': '$error'});
    }
  }

  TextStyle _style(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  Future<void> _restorePaymentSettings() async {
    final currency = _currency;
    final methodEdits = _methodEdits;
    final profileEdits = _profileEdits;
    final saved = await _wallet.loadPayments();
    final balance = await _wallet.loadBalance();
    if (!mounted) return;
    setState(() {
      if (currency == _currency) _balance = balance;
      if (methodEdits == _methodEdits) _selectedMethod = saved.defaultMethod;
      if (profileEdits == _profileEdits) _businessProfile = saved.business;
      _extraMethods = saved.extraMethods;
    });
  }

  Future<void> _savePaymentSettings() async {
    await _wallet.savePayments(
      WalletPaymentSettings(
        defaultMethod: _selectedMethod,
        business: _businessProfile,
        extraMethods: _extraMethods,
      ),
    );
  }

  void _selectMethod(String id) {
    _methodEdits++;
    setState(() => _selectedMethod = id);
    _savePaymentSettings();
  }

  void _selectProfile(bool business) {
    _profileEdits++;
    setState(() => _businessProfile = business);
    _wallet.saveBusiness(business);
  }

  Future<void> _openAddPaymentMethod() async {
    final card = await AddCardPage.open(context, cards: _cards);
    if (card == null || !mounted) return;
    _selectMethod(card.methodBrand);
  }

  /// "Remove this card?" then removes it; the default falls back to Pay in
  /// car when the removed card was the default.
  Future<void> _confirmRemoveCard(SavedCard card) async {
    final confirmed = await MoveraSheet.show<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _brandMark(card.methodBrand)),
                const SizedBox(height: 14),
                Text(
                  context.l10n.removeCardQ(card.displayName),
                  textAlign: TextAlign.center,
                  style: _style(18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.addAgainAnyTime,
                  textAlign: TextAlign.center,
                  style: _style(13, weight: FontWeight.w400, color: _muted),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('wallet-remove-card-confirm'),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF11181D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      context.l10n.removeCard,
                      style: _style(
                        15,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(
                    context.l10n.keepCard,
                    style: _style(15, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _cards.remove(card.id);
    if (!mounted) return;
    if (_selectedMethod == card.methodBrand) _selectMethod('cash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.embedded) _header(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.howToPay,
                      style: _style(27, weight: FontWeight.w700, height: 1.18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.chooseDefaultMethod,
                      style: _style(
                        11.5,
                        weight: FontWeight.w400,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 22),
                    // FLOW-11: hidden until Business does something.
                    if (widget.flags.businessProfile) ...[
                      _profileSelector(),
                      const SizedBox(height: 25),
                    ] else
                      const SizedBox(height: 3),
                    _sectionLabel(context.l10n.paymentMethodsUpper),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.035),
                            blurRadius: 22,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Offered only when there is money in the wallet.
                          if (_balance > 0) ...[
                            _paymentTile(
                              id: 'wallet',
                              title: context.l10n.moveraWallet,
                              detail: context.l10n.payFromBalance,
                              brand: 'wallet',
                            ),
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                          ],
                          if (!_isAndroid && _offers('apple_pay'))
                            _paymentTile(
                              id: 'apple',
                              title: 'Apple Pay',
                              detail: context.l10n.paysWhenSearchStarts,
                              brand: 'apple',
                              comingSoon: _soon('apple_pay'),
                            ),
                          const Divider(
                            height: 1,
                            indent: 62,
                            endIndent: 16,
                            color: _line,
                          ),
                          if (_offers('cash'))
                            _paymentTile(
                              id: 'cash',
                              title: context.l10n.payCash,
                              detail: context.l10n.payDriverCash,
                              brand: 'cash',
                            ),
                          for (final method in _extraMethods) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _paymentTile(
                              id: method['id']!,
                              title: method['title']!,
                              detail: method['detail']!,
                              brand: method['id']!,
                            ),
                          ],
                          if (_soon('card')) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _paymentTile(
                              id: 'cards',
                              title: context.l10n.payCard,
                              detail: '',
                              brand: 'cards',
                              comingSoon: true,
                            ),
                          ],
                          for (final card
                              in _offers('card') && !_soon('card')
                                  ? _cards.list()
                                  : const <SavedCard>[]) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _paymentTile(
                              id: card.methodBrand,
                              title: card.displayName,
                              detail: context.l10n.cardExpires(
                                card.expiryLabel,
                              ),
                              brand: card.methodBrand,
                              onRemove: () => _confirmRemoveCard(card),
                            ),
                          ],
                          if (CardEntryPolicy.enabled &&
                              _offers('card') &&
                              !_soon('card')) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _actionTile(
                              icon: Icons.add_rounded,
                              title: context.l10n.addCard,
                              onTap: _openAddPaymentMethod,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    _sectionLabel(context.l10n.vouchersUpper),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Semantics(
                        enabled: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 15,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.confirmation_number_outlined,
                                color: _muted,
                                size: 21,
                              ),
                              const SizedBox(width: 17),
                              Expanded(
                                child: Text(
                                  context.l10n.vouchersUnavailable,
                                  style: _style(12, color: _muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: _muted,
                          size: 15,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            context.l10n.paymentPrefsProtected,
                            style: _style(
                              9.5,
                              weight: FontWeight.w400,
                              color: _muted,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: context.l10n.back,
            child: Material(
              color: _surface,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.arrow_back_rounded, color: _ink, size: 22),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              context.l10n.navPayment,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style(13, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _profileSelector() {
    // UI-4: the 4 px frame is part of each option's target (46 px tall), not
    // padding around the 38 px options.
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _profileOption(
            label: context.l10n.profilePersonal,
            icon: Icons.person_outline_rounded,
            selected: !_businessProfile,
            onTap: () => _selectProfile(false),
            frame: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          ),
          _profileOption(
            label: context.l10n.profileBusiness,
            icon: Icons.business_center_outlined,
            selected: _businessProfile,
            onTap: () => _selectProfile(true),
            frame: const EdgeInsets.fromLTRB(0, 4, 4, 4),
          ),
        ],
      ),
    );
  }

  Widget _profileOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required EdgeInsets frame,
  }) {
    return Expanded(
      child: MoveraHitArea(
        label: label,
        selected: selected,
        onTap: onTap,
        child: Padding(
          padding: frame,
          child: Material(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onTap,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.055),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: selected ? _ink : _muted, size: 16),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(
                          11.5,
                          weight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? _ink : _muted,
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
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: _style(
        10,
        weight: FontWeight.w600,
        color: _muted,
      ).copyWith(letterSpacing: 1.25),
    );
  }

  Widget _paymentTile({
    required String id,
    required String title,
    required String detail,
    required String brand,
    VoidCallback? onRemove,
    bool comingSoon = false,
  }) {
    if (comingSoon) {
      return Opacity(
        key: ValueKey('wallet-method-$id-soon'),
        opacity: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _brandMark(brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _style(12.5, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.paymentComingSoon,
                      style: _style(
                        9.3,
                        weight: FontWeight.w400,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final selected = _selectedMethod == id;
    return Material(
      key: ValueKey('wallet-method-$id'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectMethod(id),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, onRemove == null ? 14 : 6, 12),
          child: Row(
            children: [
              _brandMark(brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(12.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? context.l10n.defaultForRides : detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        9.3,
                        weight: FontWeight.w400,
                        color: selected ? _accent : _muted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? _ink : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _ink : _line,
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : null,
              ),
              if (onRemove != null)
                IconButton(
                  key: ValueKey('wallet-remove-$id'),
                  tooltip: context.l10n.removeCard,
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: _muted,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandMark(String brand) {
    Widget logo;
    Color background = Colors.white;

    final savedCard = _cards.byMethodBrand(brand);
    if (savedCard != null) {
      logo = CardBrandLabel(savedCard.brand);
    } else if (brand == 'apple') {
      // Owner rules (G8): no Apple logo; Apple Pay is named as text.
      logo = const Icon(
        Icons.credit_card_rounded,
        color: Color(0xFF11181D),
        size: 22,
      );
    } else if (brand == 'cards') {
      // Branding rule: no Visa/Mastercard logos.
      logo = const Icon(
        Icons.credit_card_rounded,
        color: Color(0xFF11181D),
        size: 22,
      );
    } else if (brand == 'wallet' || brand.startsWith('wallet')) {
      background = const Color(0xFF11181D);
      logo = const Icon(
        Icons.account_balance_wallet_rounded,
        color: Colors.white,
        size: 20,
      );
    } else if (brand == 'cash') {
      background = const Color(0xFFEEF6F0);
      logo = const Icon(
        Icons.payments_outlined,
        color: Color(0xFF1F7A4D),
        size: 20,
      );
    } else {
      logo = const Icon(
        Icons.credit_card_rounded,
        color: Color(0xFF11181D),
        size: 22,
      );
    }

    return Container(
      width: 42,
      height: 38,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: background == Colors.white ? _line : background,
        ),
      ),
      child: brand == 'google'
          ? Transform.scale(scale: 1.18, child: logo)
          : logo,
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: _ink, size: 21),
              const SizedBox(width: 17),
              Expanded(
                child: Text(title, style: _style(12, weight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}
