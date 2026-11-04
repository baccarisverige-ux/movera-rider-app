part of 'select_ride.dart';

extension _SelectRideSheetControl on _SelectRideState {
  /// Whether [ride] has a price in this pickup's currency yet (a list price
  /// in kronor is never shown for a pickup priced in euros or dinars).
  bool _hasPrice(_RideOption ride) =>
      _selection.hasPriceFor(ride.id, catalogCurrency: ride.currency);

  List<_RideOption> get _visibleRides {
    final rides = _allRides;
    return [
      for (final ride in rides)
        if (!_SelectRideState._premiumGroup.contains(ride.id)) ride,
      for (final ride in rides)
        if (_SelectRideState._premiumGroup.contains(ride.id)) ride,
    ];
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _SelectRideState._ink,
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

  String _compactAddress(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return context.l10n.unknownPlace;
    return shortenPlace(cleaned);
  }

  /// [value] whole units of this pickup's currency, as the fare is shown.
  String _kr(double value) =>
      formatMoney(_selection.moneyOf(value), whole: true);

  /// UI-10: a price never takes more than 30% of the screen width; at large
  /// text it shrinks to fit instead of pushing the ride row off screen.
  Widget _fitPrice(BuildContext context, Widget price) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.3,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: price,
    ),
  );

  double _footerHeight(MediaQueryData media) => 134 + media.padding.bottom;

  double _headerHeight() =>
      22 +
      (_promotion == null
          ? _SelectRideState._titleHeight
          : _SelectRideState._promotionLineHeight) +
      1;

  /// Low stop: only the chosen ride above the payment block.
  double _minSheet(MediaQueryData media) =>
      (_headerHeight() +
              _SelectRideState._rowHeight +
              12 +
              _footerHeight(media))
          .clamp(240.0, math.max(240.0, media.size.height * 0.62));

  double _maxSheet(MediaQueryData media) =>
      math.max(selectRideMaxSheetHeight(media), _minSheet(media) + 120);

  /// Middle stop: about three short rows.
  double _midSheet(MediaQueryData media) => math.min(
    _minSheet(media) + _SelectRideState._rowHeight * 2 + 4,
    _maxSheet(media) - 60,
  );

  double _midValue(MediaQueryData media) {
    final range = _maxSheet(media) - _minSheet(media);
    if (range <= 0) return 1;
    return ((_midSheet(media) - _minSheet(media)) / range).clamp(0.0, 1.0);
  }

  /// The sheet's height as a fraction of the screen, which is how the
  /// draggable sheet measures its stops.
  double _fractionOf(double pixels, MediaQueryData media) =>
      (pixels / media.size.height).clamp(0.0, 1.0);

  void _snapSheetTo(double target) {
    final media = _media;
    if (media == null || !_sheetController.isAttached) return;
    _fitSlideTarget = target;
    unawaited(_fitRoute());
    final minSheet = _minSheet(media);
    final pixels = minSheet + (_maxSheet(media) - minSheet) * target;
    unawaited(
      _sheetController.animateTo(
        _fractionOf(pixels, media),
        duration: MoveraMotion.of(context, MoveraDurations.large),
        curve: MoveraCurves.snap,
      ),
    );
  }

  /// The fixed header is outside the list, so its drags move the sheet by
  /// hand and settle on the nearest stop (a fling moves one stop).
  void _onHeaderDragUpdate(DragUpdateDetails details, MediaQueryData media) {
    if (!_sheetController.isAttached) return;
    _sheetDragging = true;
    final pixels = (_sheetController.pixels - details.primaryDelta!).clamp(
      _minSheet(media),
      _maxSheet(media),
    );
    _sheetController.jumpTo(_fractionOf(pixels, media));
  }

  void _onHeaderDragEnd(DragEndDetails details, MediaQueryData media) {
    _sheetDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetSlide.value;
    final stops = <double>[0, _midValue(media), 1];
    double target;
    if (velocity < -480) {
      target = stops.firstWhere((s) => s > current + 0.01, orElse: () => 1);
    } else if (velocity > 480) {
      target = stops.lastWhere((s) => s < current - 0.01, orElse: () => 0);
    } else {
      target = stops.reduce(
        (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
      );
    }
    _snapSheetTo(target);
  }

  void _toggleSheet(MediaQueryData media) {
    _snapSheetTo(_sheetSlide.value > 0.98 ? _midValue(media) : 1);
  }

  /// A tick when the sheet lands on a new stop, and the route re-framed
  /// above it.
  bool _onSheetScroll(ScrollNotification n, MediaQueryData media) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _sheetDragging = true;
    }
    if (n is! ScrollEndNotification) return false;
    if (_sheetDragging) {
      _sheetDragging = false;
      _syncSheetOverlay();
    }
    final v = _sheetSlide.value;
    final stops = <double>[0, _midValue(media), 1];
    final nearest = stops.reduce(
      (a, b) => (a - v).abs() <= (b - v).abs() ? a : b,
    );
    if ((nearest - v).abs() > 0.02 || nearest == _settledStop) return false;
    _settledStop = nearest;
    _fitSlideTarget = null;
    HapticFeedback.selectionClick();
    _fits.settled();
    return false;
  }

  int _tripMinutes() => estimatedTripMinutes(
    GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
    GeoPoint(
      widget.destinationPosition.latitude,
      widget.destinationPosition.longitude,
    ),
  );

  /// The chosen pickup time of a scheduled ride, or null for "now".
  DateTime? get _scheduledPickup =>
      _selection.isScheduled ? _selection.scheduledFor : null;

  /// "Arrive 23:48" for [ride]: driver to pickup, then the trip. A scheduled
  /// ride is picked up at its chosen time, so only the trip counts.
  String _arrivalFor(_RideOption ride) {
    final scheduled = _scheduledPickup;
    if (scheduled != null) {
      // rider-r5-9: the trip's real time in the pickup zone (as the date
      // picker estimates it), so it holds across a clock change.
      return clockTime(
        ZoneClock.wallAfter(
          _pickupSchedule.timeZone,
          scheduled,
          Duration(minutes: _tripMinutes()),
        ),
      );
    }
    return clockTime(
      DateTime.now().add(Duration(minutes: ride.etaMin + _tripMinutes())),
    );
  }

  /// Row line under the ride name: "23:48 · 8 min" now, or
  /// "Pickup 06:55 · Arrive 07:15" for a scheduled ride.
  String _timesFor(_RideOption ride) {
    final scheduled = _scheduledPickup;
    if (scheduled != null) {
      return context.l10n.pickupAtArriveAt(
        clockTime(scheduled),
        _arrivalFor(ride),
      );
    }
    // Owner round 2, like the other ride apps: "07:14 · 8 min" (when you
    // arrive · how far the car is).
    return context.l10n.arriveEtaMin(_arrivalFor(ride), '${ride.etaMin}');
  }

  /// Frames the route above the sheet. [force] flies an unchanged framing
  /// too (a newly created map starts from its own camera).
  Future<void> _fitRoute({bool force = false}) => _fits.fit(force: force);

  /// rider-74: the wallet alone cannot pay a fare above its balance. Says
  /// so and returns true when the wallet is the chosen method for it.
  bool _walletCannotPay(double priceKr) {
    if (_selection.selectedPaymentItem()?.brand != 'wallet' ||
        _selection.walletCovers(priceKr)) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.walletTooLowChooseAnother)),
    );
    return true;
  }

  /// Phase 114/136: a return ride arrives with a prefilled pickup
  /// (origin + 3 h) that nobody validated. Before it can be booked it must
  /// satisfy the same [StockholmSchedule] rules the scheduling picker
  /// enforces (30-minute lead, 5-minute slots) — lead time alone isn't
  /// enough, since a prefill can be legal but still off-grid (e.g. 21:07).
  /// The main Schedule flow already picked its time in that picker, so it is
  /// not re-checked here.
  bool get _returnTimeNeedsPicker {
    if (widget.parentReservationId == null) return false;
    final when = _selection.scheduledFor;
    return when != null &&
        (!_pickupSchedule.isLegalPickup(when) ||
            !StockholmSchedule.isOnGrid(when) ||
            // rider-r4-10: nor past the zone's reservation horizon.
            ZoneClock.wall(when).isAfter(
              _pickupSchedule.latestPickup(_pickupSchedule.horizonDays),
            ));
  }

  /// Q9: Book later times are the pickup zone's wall-clock time.
  PickupSchedule get _pickupSchedule => PickupSchedule.at(
    _pickupPosition.latitude,
    _pickupPosition.longitude,
    config: _zoneConfig,
  );
}
