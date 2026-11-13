part of 'select_ride.dart';

extension _SelectRideTiles on _SelectRideState {
  /// The sheet's content. Built with the screen, not with the sheet's
  /// position: the parts that follow the position (the list fading in
  /// above the low stop, the descriptions growing in towards the full stop,
  /// the handle's label and the chosen ride shown at the low stop) each
  /// listen to [_sheetSlide] on their own, so a drag tick rebuilds no row.
  /// Owner (iPhone PWA): rebuilding every row, its fonts and its times on
  /// each tick of the drag was most of the frame
  /// (docs/select-ride-sheet-performance.md).
  Widget _sheetBody(MediaQueryData media, ScrollController scroll) {
    final mid = _midValue(media);
    // 0 at the low stop → 1 at the middle: the other rides come in.
    final listReveal = _sheetSlide.drive(_ListReveal(mid));
    // 0 at the middle → 1 at full: descriptions and badges.
    final detail = _sheetSlide.drive(_DetailReveal(mid));
    final selectedRide = _selectedRideOrNull;
    final promotion = _promotion;
    final entries = _listEntries;
    return Column(
      children: [
        // Title, promotion and filters stay put while the rides scroll
        // under them; dragging here still moves the sheet.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) =>
              _onHeaderDragUpdate(details, media),
          onVerticalDragEnd: (details) => _onHeaderDragEnd(details, media),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _sheetSlide,
                builder: (context, child) => Semantics(
                  button: true,
                  label: _sheetSlide.value > 0.98
                      ? context.l10n.showFewerRides
                      : context.l10n.showAllRides,
                  child: child,
                ),
                child: GestureDetector(
                  key: const ValueKey('select-ride-sheet-handle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSheet(media),
                  child: SizedBox(
                    width: double.infinity,
                    height: 22,
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _SelectRideState._line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Owner round 2: a teal "promotion applied" line like the
              // other ride apps; without one, the title.
              if (promotion != null)
                _promotionLine(promotion)
              else
                SizedBox(
                  height: _SelectRideState._titleHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.chooseYourRide,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          20,
                          weight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              const Divider(
                height: 1,
                thickness: 1,
                color: _SelectRideState._line,
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FadeTransition(
                opacity: listReveal,
                child: ListView.builder(
                  key: const ValueKey('select-ride-list'),
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(
                    14,
                    2,
                    14,
                    _footerHeight(media) + 8,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final ride = entry.ride;
                    if (ride != null) {
                      return _rideTile(ride, detail: detail);
                    }
                    return _groupHeading(
                      entry.heading!,
                      detail: detail,
                      first: index == 0,
                    );
                  },
                ),
              ),
              // At the low stop only the chosen ride shows.
              if (selectedRide != null)
                AnimatedBuilder(
                  animation: listReveal,
                  builder: (context, child) {
                    final reveal = listReveal.value;
                    return Positioned(
                      left: 14,
                      right: 14,
                      top: 2,
                      child: Offstage(
                        offstage: reveal >= 1,
                        child: IgnorePointer(
                          ignoring: reveal > 0.5,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: FadeTransition(
                    opacity: ReverseAnimation(listReveal),
                    // Owner round 3: a swipe on the chosen ride moves the
                    // sheet too.
                    child: GestureDetector(
                      key: const ValueKey('select-ride-low-row-drag'),
                      onVerticalDragUpdate: (d) =>
                          _onHeaderDragUpdate(d, media),
                      onVerticalDragEnd: (d) => _onHeaderDragEnd(d, media),
                      child: ColoredBox(
                        color: Colors.white,
                        child: _rideTile(
                          selectedRide,
                          detail: const AlwaysStoppedAnimation<double>(0),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _SelectRideState._line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF162C36).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: _SelectRideState._ink,
              ),
              tooltip: context.l10n.back,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _compactAddress(widget.destinationAddress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(15, weight: FontWeight.w500),
                  ),
                  // UI-08: the stops the price includes.
                  if (viaStopsLine(_locatedStops.map((s) => s.address))
                      case final via?)
                    Text(
                      via,
                      key: const ValueKey('select-ride-via-stops'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(12, color: _SelectRideState._muted),
                    ),
                  if (_stopsNotice case final notice?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        notice,
                        key: const ValueKey('select-ride-stops-left-out'),
                        style: _text(
                          12,
                          weight: FontWeight.w500,
                          color: const Color(0xFFB42318),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_stopsRetry)
              TextButton(
                key: const ValueKey('select-ride-stops-retry'),
                onPressed: _retryStops,
                child: Text(
                  context.l10n.tryAgain,
                  style: _text(
                    13,
                    weight: FontWeight.w600,
                    color: _SelectRideState._ink,
                  ),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// "30 % promotion applied ⓘ" in teal; tap for the details.
  Widget _promotionLine(RiderPromotion promotion) {
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('select-ride-promotion-line'),
        onTap: () => _openPromotionDetails(promotion),
        child: SizedBox(
          height: _SelectRideState._promotionLineHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_offer_rounded,
                  size: 17,
                  color: _SelectRideState._teal,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    context.l10n.promotionApplied('${promotion.percentOff}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      15.5,
                      weight: FontWeight.w600,
                      color: _SelectRideState._tealText,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: _SelectRideState._tealText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Rides for you" / "Premium": shown once the sheet is fully up.
  Widget _groupHeading(
    String text, {
    required Animation<double> detail,
    required bool first,
  }) {
    return _SelectRideState._reveal(
      detail,
      Padding(
        padding: EdgeInsets.fromLTRB(8, first ? 10 : 18, 8, 8),
        child: Semantics(
          header: true,
          child: Text(
            text,
            key: ValueKey('select-ride-heading-$text'),
            style: _text(19, weight: FontWeight.w700, letterSpacing: -0.3),
          ),
        ),
      ),
    );
  }

  /// Every category's price before and after the promotion, from the quotes
  /// we have right now; categories still waiting for a quote are left out.
  Map<String, PromotionPrice> _promotionPrices() {
    final prices = <String, PromotionPrice>{};
    for (final ride in _allRides) {
      final quote = _selection.authoritativeQuotes[ride.id];
      if (quote == null) continue;
      final discounted = Money(quote.totalMinor, quote.currency).major;
      prices[ride.id] = (
        original: Money(
          quote.totalMinor + quote.discountMinor,
          quote.currency,
        ).major,
        discounted: discounted,
      );
    }
    return prices;
  }

  /// The promo ticket opens the details with this screen's current prices.
  Future<void> _openPromotionDetails(RiderPromotion promotion) {
    return PromotionDetailsSheet.open(
      context,
      promotion,
      categories: [
        for (final ride in _allRides)
          PromotionCategory(id: ride.id, name: ride.name),
      ],
      prices: _promotionPrices(),
      currency: _selection.currency,
    );
  }

  /// The quote's discount for [ride], in kr (0 when none).
  double _discountFor(_RideOption ride) {
    final quote = _selection.authoritativeQuotes[ride.id];
    if (quote == null || quote.discountMinor <= 0) return 0;
    return Money(quote.discountMinor, quote.currency).major;
  }

  Widget _rideTile(_RideOption ride, {required Animation<double> detail}) {
    final selected = ride.id == _selection.selectedRideId;
    final price = _priceFor(ride);
    final discount = _discountFor(ride);
    // rider-u191: the category that will be booked is announced.
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('select-ride-tile-${ride.id}'),
            onTap: () => _selectRide(ride.id),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(
                minHeight: _SelectRideState._rowHeight - 4,
              ),
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? _SelectRideState._selectedOutline
                      : Colors.transparent,
                  width: 2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF162C36,
                          ).withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // Owner round 2: the white car like the other ride
                  // apps, with what tells the type apart beside it.
                  RidePicture(
                    rideId: ride.id,
                    glyph: ride.glyphKey,
                    glyphIcon: ride.glyph,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    flex: 5,
                                    child: Text(
                                      rideNameFor(ride.name),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _text(16, weight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Icon(
                                    Icons.person_rounded,
                                    size: 14,
                                    color: _SelectRideState._ink,
                                  ),
                                  Flexible(
                                    child: Text(
                                      '${ride.seats}',
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: _text(
                                        13,
                                        color: _SelectRideState._ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (discount > 0) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.local_offer_rounded,
                                  size: 14,
                                  color: _SelectRideState._teal,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            _fitPrice(
                              context,
                              Text(
                                // No quote yet for a pickup outside the
                                // list's currency: no price, not a wrong one.
                                _hasPrice(ride) ? _kr(price) : '…',
                                style: _text(16, weight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _timesFor(ride),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  13.5,
                                  color: _SelectRideState._ink,
                                  weight: FontWeight.w400,
                                ),
                              ),
                            ),
                            if (discount > 0)
                              _fitPrice(
                                context,
                                Text(
                                  _kr(price + discount),
                                  // UI-6: was 0xFF8A9399 (3.13:1 on white).
                                  style:
                                      _text(
                                        12,
                                        color: MoveraTokens.subtleOnFill,
                                      ).copyWith(
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        // rider-80: no split worked out from a list price
                        // the tile itself does not show ('…').
                        if (selected &&
                            _hasPrice(ride) &&
                            _selection
                                .walletSplitFor(
                                  _selection.moneyOf(price).amountMinor,
                                )
                                .usesWallet)
                          _walletLine(price),
                        if (selected && _walletOtherCurrency)
                          _walletCurrencyNote(),
                        if (_outstandingFeeOf(ride) case final fee?)
                          _outstandingFeeLine(ride, fee),
                        // Description and badge come in as the sheet opens
                        // fully.
                        _SelectRideState._reveal(
                          detail,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                ride.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  12.5,
                                  color: _SelectRideState._muted,
                                  weight: FontWeight.w400,
                                ),
                              ),
                              if (ride.badge != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _SelectRideState._accent
                                        : _SelectRideState._accentSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ride.badge!,
                                    style: _text(
                                      9.5,
                                      weight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : _SelectRideState._accent,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
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

  /// Under the selected ride: what the wallet covers and what is left to
  /// pay. The list price itself stays the real fare.
  /// The rider has wallet money and wants it used, but it is in another
  /// currency than this trip: it is not used (no conversion).
  bool get _walletOtherCurrency =>
      _selection.useWalletFirst &&
      _selection.walletBalance > 0 &&
      !_selection.walletMatchesTrip &&
      _selection.walletEnabled;

  /// Live sweep 2026-11-02 M-1: the old unpaid fee inside this price
  /// (`fareLines.outstanding_fee`), or null.
  Money? _outstandingFeeOf(_RideOption ride) =>
      _selection.unpaidFeeFor(ride.id);

  Widget _outstandingFeeLine(_RideOption ride, Money fee) => Padding(
    key: ValueKey('select-ride-outstanding-fee-${ride.id}'),
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      // Owner 2026-11-07 (item 12): one short line.
      context.l10n.priceUnpaidFeeShort(formatMoneyShort(fee)),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _text(12, color: _SelectRideState._muted),
    ),
  );

  Widget _walletCurrencyNote() => Padding(
    key: const ValueKey('select-ride-wallet-currency-note'),
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      context.l10n.walletWrongCurrency(
        _selection.walletCurrency,
        _selection.currency,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _text(12, color: _SelectRideState._muted),
    ),
  );

  Widget _walletLine(double price) {
    final split = _selection.walletSplitFor(
      _selection.moneyOf(price).amountMinor,
    );
    const green = Color(0xFF079A60);
    return Padding(
      key: const ValueKey('select-ride-wallet-line'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 13,
            color: green,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fix job 5 (v0.18.33, owner Q6): the per-ride switch is on.
                // B1 (finder 2026-11-07): both wallet lines wrap instead of
                // ending in "…": at 320-390 px in fr/sv the amount the rider
                // pays was cut off. The tile grows only when it is selected
                // and uses the wallet.
                Text(
                  context.l10n.walletUsedFirst,
                  key: const ValueKey('select-ride-wallet-used-first'),
                  style: _text(12, weight: FontWeight.w600, color: green),
                ),
                split.paidByWallet
                    ? Text(
                        context.l10n.paidByWallet,
                        style: _text(12, weight: FontWeight.w600, color: green),
                      )
                    : Text(
                        context.l10n.walletSplit(
                          split.walletLabel,
                          split.remainderLabel,
                        ),
                        key: const ValueKey('select-ride-wallet-split'),
                        style: _text(12, weight: FontWeight.w500, color: green),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentButton() {
    final item = _selection.selectedPaymentItem();
    final method = item == null
        ? _PaymentOption(brand: 'cash', name: context.l10n.payCash, detail: '')
        : _PaymentOption(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
          );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('select-ride-payment'),
        // rider-u189: Set pickup changes the method of a booking under way.
        onTap: _bookingInFlight ? null : _showPaymentPicker,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              const SizedBox(width: 4),
              _brandMark(method.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            paymentNameFor(method.brand, method.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(15, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      paymentDetailFor(method.brand, method.detail),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        11.5,
                        weight: FontWeight.w500,
                        color: method.brand == 'cash'
                            ? _SelectRideState._accent
                            : _SelectRideState._muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _SelectRideState._ink,
                size: 22,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _SelectRideState._accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _SelectRideState._accent : _SelectRideState._line,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _SelectRideState._ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _text(16, weight: FontWeight.w600)),
                  Text(
                    subtitle,
                    style: _text(13, color: _SelectRideState._muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
