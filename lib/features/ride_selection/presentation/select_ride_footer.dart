part of 'select_ride.dart';

extension _SelectRideFooter on _SelectRideState {
  /// The price the rider books at: the server quote when it is in, else
  /// the list price. Null in another currency than the zone's rules.
  Money? _bookingFare(_RideOption ride) {
    final quote = _selection.authoritativeQuotes[ride.id];
    final fare = quote != null
        ? Money(quote.totalMinor, quote.currency)
        : Money.fromLegacyMajor(ride.price, ride.currency);
    final zone = _zoneConfig;
    return zone == null || zone.currency == fare.currency ? fare : null;
  }

  /// The fixed bottom block: one thin payment line, then Book.
  Widget _footer(double bottomInset) {
    final selected = _selectedRideOrNull;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 6, 16, 12 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _SelectRideState._line)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF162C36).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // LOW 12: the booking summary says the free change / cancel rule.
          if (_scheduledPickup != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                ReservationFormat.freeRule(
                  _zoneConfig?.freeChangeBeforeMin ??
                      RiderAppConfig.defaultFreeChangeBeforeMin,
                  // v0.18.49 Q10: the selected category's cancel rule.
                  rule: selected == null
                      ? null
                      : _zoneConfig?.reservationFeeFor(selected.id),
                  fare: selected == null ? null : _bookingFare(selected),
                ),
                key: const ValueKey<String>('select-ride-free-rule'),
                textAlign: TextAlign.center,
                style: _text(
                  11.5,
                  weight: FontWeight.w500,
                  color: _SelectRideState._muted,
                ),
              ),
            ),
          _paymentButton(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: _SelectRideState._cta,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _bookingInFlight ? null : _book,
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 54,
                      child: Center(
                        child: Text(
                          selected == null
                              ? context.l10n.noRidesAvailable
                              : _selection.bookingMode.ctaLabel(
                                  rideNameFor(selected.name),
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(
                            16,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // UI-5: the icon-only button has a name for screen readers.
              Semantics(
                button: true,
                label: context.l10n.bookNowOrLater,
                child: Material(
                  color: _SelectRideState._cta,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _showBookingPicker,
                    child: const SizedBox(
                      width: 54,
                      height: 54,
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brandMark(String brand) {
    Widget logo;
    Color background = Colors.white;
    final savedCard = _selection.savedCardFor(brand);
    if (savedCard != null) {
      logo = CardBrandLabel(savedCard.brand);
    } else if (brand == 'apple' || brand == 'cards') {
      // Owner rules: no other company's logo (Apple Pay is named as text).
      logo = const Icon(
        Icons.credit_card_rounded,
        color: Color(0xFF11181D),
        size: 22,
      );
    } else if (brand == 'cash') {
      background = const Color(0xFFEEF6F0);
      logo = const Icon(
        Icons.directions_car_filled_outlined,
        color: Color(0xFF1F7A4D),
        size: 20,
      );
    } else {
      logo = Image.asset(
        excludeFromSemantics: true,
        AppAssets.wallet,
        color: _SelectRideState._ink,
        fit: BoxFit.contain,
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
          color: background == Colors.white
              ? _SelectRideState._line
              : background,
        ),
      ),
      child: logo,
    );
  }
}
