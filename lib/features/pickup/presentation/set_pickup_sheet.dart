part of 'set_pickup_page.dart';

// Rule 25 split (2026-11-07, no behaviour change): the Set pickup sheet's
// sections (ride header, pickup card, spot chips, bags, price, payment,
// confirm button), moved out of set_pickup_page.dart unchanged.
extension _SetPickupSheet on _SetPickupPageState {
  /// Folds a section away as the sheet slides down; staggered by [start].
  Widget _reveal(double start, double end, Widget child) {
    final curve = _reveals.putIfAbsent(
      (start, end),
      () => CurvedAnimation(
        parent: _sheet,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 10 * (1 - curve.value)),
            child: child,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _rideHeader() {
    final ride = widget.ride;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 46,
            child: Image.asset(
              ride.image,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_car_filled_rounded,
                color: _SetPickupPageState._muted,
                size: 34,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rideNameFor(ride.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(19, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: _SetPickupPageState._muted,
                    ),
                    Text(
                      '${ride.seats}',
                      style: _text(
                        13.5,
                        weight: FontWeight.w600,
                        color: _SetPickupPageState._muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _timesLine,
                  style: _text(13, color: _SetPickupPageState._muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupCard() {
    final spot = _selectedSpot;
    final subtitle = _resolving
        ? context.l10n.findingTheAddress
        : spot != null
        ? spot.subtitle
        : _atCurrentLocation
        ? context.l10n.yourCurrentLocation
        : context.l10n.dragMapToAdjust;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _searchAddress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _SetPickupPageState._accent, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: RiderRouteStyle.pickup,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _address,
                        key: ValueKey(_address),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(15.5, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: _text(12.5, color: _SetPickupPageState._accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.change,
                style: _text(
                  14,
                  weight: FontWeight.w600,
                  color: _SetPickupPageState._accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    VoidCallback onTap, {
    IconData? icon,
    bool selected = false,
    Key? key,
  }) {
    final fg = selected ? Colors.white : _SetPickupPageState._ink;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _SetPickupPageState._cta : _SetPickupPageState._field,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? _SetPickupPageState._cta
                : _SetPickupPageState._line,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: _text(13.5, weight: FontWeight.w500, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Spots for the address under the pin, then "On map" to place the pin
  /// by hand. The chosen spot is filled black.
  Widget _spotChips() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        key: const ValueKey('set-pickup-spots'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final spot in _spots)
              Semantics(
                button: true,
                selected: _selectedSpot?.id == spot.id,
                label: '${spot.title}, ${spot.subtitle}',
                child: _chip(
                  spot.title,
                  () => _useSpot(spot),
                  icon: _SetPickupPageState._spotIcon(spot.kind),
                  selected: _selectedSpot?.id == spot.id,
                  key: ValueKey('set-pickup-spot-${spot.id}'),
                ),
              ),
            _chip(
              context.l10n.onMap,
              () => _settleSheet(false),
              icon: Icons.add_rounded,
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _bagLabels => [context.l10n.bagsNone, '1–2', '3+'];

  /// On the short sheet the bags sit at the top right; a tap cycles
  /// No → 1–2 → 3+. The chip fades away as the sheet opens, where the full
  /// Bags row takes over.
  Widget _shortBagsChip() {
    return AnimatedBuilder(
      animation: _sheet,
      builder: (context, child) {
        final visible = (1 - _sheet.value * 2).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: visible < 0.5,
          child: Opacity(opacity: visible, child: child),
        );
      },
      child: Semantics(
        button: true,
        label: context.l10n.bagsLabel(_bagLabels[_bags]),
        child: GestureDetector(
          key: const ValueKey('set-pickup-bags-chip'),
          onTap: () {
            HapticFeedback.selectionClick();
            // ignore: invalid_use_of_protected_member
            setState(() => _bags = (_bags + 1) % _bagLabels.length);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: _bags == 0
                  ? const Color(0xFFF3F5F6)
                  : _SetPickupPageState._accent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _bags == 0
                    ? _SetPickupPageState._line
                    : _SetPickupPageState._accent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.luggage_rounded,
                  size: 16,
                  color: _bags == 0
                      ? _SetPickupPageState._accent
                      : Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _bags == 0
                      ? context.l10n.notesBags
                      : context.l10n.bagsCount(_bagLabels[_bags]),
                  style: _text(
                    12.5,
                    weight: FontWeight.w600,
                    color: _bags == 0 ? _SetPickupPageState._ink : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bagsRow() {
    final labels = _bagLabels;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const Icon(
            Icons.luggage_rounded,
            color: _SetPickupPageState._accent,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.bagsQuestion,
              style: _text(15, weight: FontWeight.w600),
            ),
          ),
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: Semantics(
                selected: _bags == i,
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    // ignore: invalid_use_of_protected_member
                    setState(() => _bags = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _bags == i
                          ? _SetPickupPageState._accent
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _bags == i
                            ? _SetPickupPageState._accent
                            : _SetPickupPageState._line,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: _text(
                        13.5,
                        weight: FontWeight.w600,
                        color: _bags == i
                            ? Colors.white
                            : _SetPickupPageState._ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool bold = false,
    Color color = _SetPickupPageState._ink,
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: _text(
                14.5,
                weight: bold ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
          Text(
            value,
            style: _text(
              14.5,
              weight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceBox() {
    final fare = _fare;
    final hasDiscount = fare.discountKr > 0;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _SetPickupPageState._line),
      ),
      child: Column(
        children: [
          if (hasDiscount) ...[
            _priceRow(
              context.l10n.ridePrice,
              fare.format(fare.totalKr + fare.discountKr),
            ),
            _priceRow(
              fare.promotionPercent == null
                  ? context.l10n.promotion
                  : context.l10n.promotionPercent('${fare.promotionPercent}'),
              '-${fare.format(fare.discountKr)}',
              color: _SetPickupPageState._accent,
            ),
            const Divider(height: 12, color: _SetPickupPageState._line),
          ],
          _priceRow(context.l10n.total, fare.format(fare.totalKr), bold: true),
          if (fare.split.usesWallet) ...[
            const Divider(height: 12, color: _SetPickupPageState._line),
            _priceRow(
              context.l10n.moveraWallet,
              '-${fare.split.walletLabel}',
              color: _SetPickupPageState._walletGreen,
              key: const ValueKey('set-pickup-wallet-part'),
            ),
            _priceRow(
              fare.split.paidByWallet
                  ? context.l10n.nothingMoreToPay
                  : paymentNameFor(_payment.brand, _payment.name),
              fare.split.remainderLabel,
              key: const ValueKey('set-pickup-remainder'),
            ),
          ],
          if (_requoting)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                context.l10n.updatingPrice,
                key: const ValueKey('set-pickup-requoting'),
                style: _text(12.5, color: _SetPickupPageState._muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentLine() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onChangePayment == null ? null : _changePayment,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 32,
                child: Center(child: widget.brandMark(_payment.brand)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // rider-u142: the catalog's English name and line
                    // ('Cash', 'Pay the driver in cash') as Select Ride
                    // shows them, in the app language.
                    Text(
                      paymentNameFor(_payment.brand, _payment.name),
                      style: _text(14.5, weight: FontWeight.w600),
                    ),
                    if (_payment.detail.trim().isNotEmpty)
                      Text(
                        paymentDetailFor(_payment.brand, _payment.detail),
                        style: _text(12.5, color: _SetPickupPageState._muted),
                      ),
                  ],
                ),
              ),
              if (widget.onChangePayment != null)
                Text(
                  context.l10n.changeArrow,
                  style: _text(
                    14,
                    weight: FontWeight.w600,
                    color: _SetPickupPageState._accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        key: const ValueKey('set-pickup-confirm'),
        onPressed: _usable ? () => unawaited(_confirm()) : null,
        style: FilledButton.styleFrom(
          backgroundColor: _SetPickupPageState._cta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _confirmWaiting
            ? const SizedBox(
                key: ValueKey('set-pickup-confirm-waiting'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.confirmLabel ?? context.l10n.confirmAndSearch,
                style: _text(16, weight: FontWeight.w600, color: Colors.white),
              ),
      ),
    );
  }
}
