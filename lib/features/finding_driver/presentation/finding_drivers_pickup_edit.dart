part of 'finding_drivers.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Owner 2026-11-23 (approved search screen): the rider's own marker, the
/// share-location sheet, the locked pickup with "Justera" and its edit
/// mode, and the round quick actions of the pulled-up sheet.
extension _FindingDriversSearchExtras on _FindingDriversState {
  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  Future<void> _prepareSearchMarks() async {
    final label = L10n.current.fdAdjustPill;
    final icons = await Future.wait<BitmapDescriptor>([
      SearchingRiderMarker.createIcon(known: true),
      for (var i = 0; i < 4; i++)
        SearchingRiderMarker.createIcon(known: false, pulse: i / 4),
      AdjustPillMarker.createIcon(label),
    ]);
    if (!mounted) return;
    _riderKnownIcon = icons[0];
    for (var i = 0; i < 4; i++) {
      _riderOffIcons[i] = icons[1 + i];
    }
    _adjustIcon = icons[5];
    _loadMapBits();
    setState(() {});
  }

  Future<void> _readRiderFix() async {
    final fix = await _riderLocation.current();
    if (!mounted) return;
    _setRiderFix(fix);
  }

  void _setRiderFix(GeoPoint? fix) {
    _riderFix = fix;
    _syncPulse();
    _loadMapBits();
    setState(() {});
  }

  /// The grey marker pulses gently (never with reduce motion).
  void _syncPulse() {
    final pulse = _riderFix == null && !_reduceMotion;
    if (!pulse) {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      _pulseStep = 0;
      return;
    }
    _pulseTimer ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      _pulseStep = (_pulseStep + 1) % 4;
      _loadMapBits();
      setState(() {});
    });
  }

  /// The rider's marker: blue at the fix; grey (with "!") beside the
  /// pickup when there is no location.
  Marker? _riderMarker() {
    final fix = _riderFix;
    if (fix != null) {
      final icon = _riderKnownIcon;
      if (icon == null) return null;
      return Marker(
        markerId: const MarkerId('rider-known'),
        position: LatLng(fix.latitude, fix.longitude),
        icon: icon,
        anchor: SearchingRiderMarker.anchor,
        zIndexInt: 1,
        infoWindow: InfoWindow(title: L10n.current.fdYourLocation),
      );
    }
    final icon = _riderOffIcons[_pulseStep] ?? _riderOffIcons[0];
    if (icon == null) return null;
    final last = LocationRepository.sessionFix;
    return Marker(
      markerId: const MarkerId('rider-unknown'),
      position: last != null
          ? LatLng(last.latitude, last.longitude)
          : _pickupPosition,
      icon: icon,
      // No position at all: drawn just below left of the pickup pin.
      anchor: last != null ? SearchingRiderMarker.anchor : const Offset(1, 0),
      zIndexInt: 1,
      consumeTapEvents: true,
      onTap: () => unawaited(_openShareLocation()),
    );
  }

  /// The "Justera" pill beside the locked pickup pin.
  Marker? _adjustMarker() {
    final icon = _adjustIcon;
    if (icon == null || _editingPickup || _match.matchCount > 0) return null;
    return Marker(
      markerId: const MarkerId('pickup-adjust'),
      position: _pickupPosition,
      icon: icon,
      anchor: AdjustPillMarker.anchor,
      zIndexInt: 2,
      consumeTapEvents: true,
      onTap: _startPickupEdit,
    );
  }

  Future<void> _openShareLocation() async {
    if (_shareSheetOpen || _leaving || _editingPickup) return;
    _shareSheetOpen = true;
    final share = await showShareLocationSheet(context);
    _shareSheetOpen = false;
    if (share && mounted) {
      final fix = await _riderLocation.request();
      if (mounted && fix != null) _setRiderFix(fix);
    }
    if (mounted) _drainDeferredNavigation();
  }

  // ---- pickup edit mode ----

  /// The trip zone's `booking.maxPickupMoveMeters` (never hard-coded).
  int get _maxPickupMeters =>
      _zoneConfig?.maxPickupMoveMeters ??
      RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters;

  double get _editMeters => GeoDistance.metersBetween(
    _pickupPosition.latitude,
    _pickupPosition.longitude,
    _editTarget.latitude,
    _editTarget.longitude,
  );

  bool get _editBeyond => _editMeters > _maxPickupMeters;

  void _startPickupEdit() {
    if (_leaving || _editingPickup || _match.matchCount > 0) return;
    _editingPickup = true;
    _editTarget = _pickupPosition;
    _editAddress = _shortPlace(_pickupAddress);
    _editQuote = null;
    _editSeq++;
    _loadMapBits();
    setState(() {});
    unawaited(
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_pickupPosition, 16),
      ),
    );
  }

  void _onEditCameraMove(CameraPosition position) {
    if (!_editingPickup) return;
    _editTarget = position.target;
    _editQuote = null;
  }

  Future<void> _onEditCameraIdle() async {
    if (!_editingPickup) return;
    final seq = ++_editSeq;
    final target = _editTarget;
    final point = GeoPoint(target.latitude, target.longitude);
    final address = await _pickupEditor.addressAt(point);
    if (!mounted || seq != _editSeq) return;
    if (address != null && address.trim().isNotEmpty) _editAddress = address;
    setState(() {});
    if (!_editBeyond) return;
    final ride = _match.ownershipSnapshot;
    if (ride == null) return;
    final quote = await _pickupEditor.quote(ride, _editAddress, point);
    if (!mounted || seq != _editSeq) return;
    setState(() => _editQuote = quote);
  }

  void _endPickupEdit() {
    _editingPickup = false;
    _editQuote = null;
    _editBusy = false;
    _editSeq++;
    _loadMapBits();
    setState(() {});
  }

  Future<void> _confirmPickupEdit() async {
    final ride = _match.ownershipSnapshot;
    if (ride == null || _editBusy) return;
    final beyond = _editBeyond;
    if (beyond && _editQuote == null) return;
    setState(() => _editBusy = true);
    final point = GeoPoint(_editTarget.latitude, _editTarget.longitude);
    final updated = await _pickupEditor.apply(
      context,
      ride,
      _editAddress,
      point,
      beyond ? _editQuote : null,
    );
    if (!mounted) return;
    if (updated == null) {
      setState(() => _editBusy = false);
      return;
    }
    _applyRouteChange(updated);
    _endPickupEdit();
    showRouteUpdated(
      context,
      driverAssigned: false,
      paymentMethod: widget.paymentMethod,
      differenceKr: lastRouteDifferenceKr ?? updated.price - ride.price,
      currency: updated.currency,
      newPrice: beyond ? updated.price : null,
    );
  }

  Future<void> _searchPickup() async {
    final ride = _match.ownershipSnapshot;
    if (ride == null) return;
    final picked = await _pickupEditor.search(context, ride);
    if (!mounted || picked == null) return;
    _editTarget = LatLng(picked.point.latitude, picked.point.longitude);
    _editAddress = picked.address;
    await _mapController?.animateCamera(CameraUpdate.newLatLng(_editTarget));
    if (mounted) unawaited(_onEditCameraIdle());
  }

  void _recenterOnRider() {
    final fix = _riderFix;
    final target = fix != null
        ? LatLng(fix.latitude, fix.longitude)
        : _pickupPosition;
    unawaited(_mapController?.animateCamera(CameraUpdate.newLatLng(target)));
  }

  /// The free zone: a circle of `maxPickupMoveMeters` round the booked
  /// pickup, the map outside it dimmed.
  Set<Circle> get _editCircles => !_editingPickup
      ? const <Circle>{}
      : {
          Circle(
            circleId: const CircleId('pickup-free-zone'),
            center: _pickupPosition,
            radius: _maxPickupMeters.toDouble(),
            strokeWidth: 2,
            strokeColor: AppColor.blue.withValues(alpha: 0.55),
            fillColor: Colors.white.withValues(alpha: 0.18),
          ),
        };

  Set<Polygon> get _editPolygons {
    if (!_editingPickup) return const <Polygon>{};
    final c = _pickupPosition;
    final r = _maxPickupMeters.toDouble();
    final dLat = r / 111320;
    final dLng = r / (111320 * math.cos(c.latitude * math.pi / 180));
    return {
      Polygon(
        polygonId: const PolygonId('pickup-free-zone-dim'),
        points: [
          LatLng(c.latitude - 1, c.longitude - 1),
          LatLng(c.latitude - 1, c.longitude + 1),
          LatLng(c.latitude + 1, c.longitude + 1),
          LatLng(c.latitude + 1, c.longitude - 1),
        ],
        holes: [
          [
            for (var i = 0; i < 48; i++)
              LatLng(
                c.latitude + dLat * math.sin(2 * math.pi * i / 48),
                c.longitude + dLng * math.cos(2 * math.pi * i / 48),
              ),
          ],
        ],
        strokeWidth: 0,
        fillColor: const Color(0x2E1D252C),
        consumeTapEvents: false,
      ),
    };
  }

  /// "+16 kr" beside the pin, once the move beyond the zone is priced.
  String? get _editExtra {
    final quote = _editQuote;
    if (!_editBeyond || quote == null) return null;
    return '+${formatMajor(quote.differenceKr, quote.currency)}';
  }

  /// The edit mode's layers over the map: the centred pin, ✕, the
  /// my-location button and the compact card.
  List<Widget> _editLayers(MediaQueryData media, double mapBottom) {
    final quote = _editBeyond ? _editQuote : null;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: mapBottom,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -60),
            child: PickupEditPin(
              label: _editAddress,
              beyond: _editBeyond,
              extra: _editExtra,
            ),
          ),
        ),
      ),
      Positioned(
        top: media.padding.top + 8,
        left: 12,
        child: PointerInterceptor(
          child: MoveraIconButton.round(
            key: const ValueKey('pickup-edit-close'),
            icon: Icons.close_rounded,
            onPressed: _endPickupEdit,
            label: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: PointerInterceptor(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 16),
                child: MoveraIconButton.round(
                  key: const ValueKey('pickup-edit-my-location'),
                  icon: Icons.my_location_rounded,
                  onPressed: _recenterOnRider,
                  label: context.l10n.recenterMap,
                ),
              ),
              PickupEditCard(
                address: _editAddress,
                busy: _editBusy,
                oldPrice: quote?.oldPriceKr,
                newPrice: quote?.newPriceKr,
                currency: quote?.currency ?? _match.currency,
                onSearch: () => unawaited(_searchPickup()),
                onConfirm: _editBeyond && quote == null
                    ? null
                    : () => unawaited(_confirmPickupEdit()),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ---- pulled-up sheet: round quick actions ----

  /// Opens [page] over the parked map, like the route screen.
  Future<void> _coverWith(Future<void> Function() open) async {
    if (_pickupEditOpen || _leaving) return;
    AppScope.instance.maps.detach(owner: MapOwners.finding);
    setState(() {
      _mapParked = true;
      _pickupEditOpen = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await open();
    if (!mounted) return;
    setState(() {
      _mapParked = false;
      _pickupEditOpen = false;
    });
    _drainDeferredNavigation();
  }

  Widget _quickActions() {
    final l10n = context.l10n;
    Widget action(String key, String icon, String label, VoidCallback onTap) {
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: MoveraTokens.line),
                    ),
                    alignment: Alignment.center,
                    child: AppIconAsset(icon, size: 22, color: AppColor.navy),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: MoveraTokens.ink,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      key: const ValueKey('finding-quick-actions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        action(
          'qa-add-stop',
          AppAssets.solarAdd,
          l10n.addStop,
          () => unawaited(_changeRoute(null, RouteChangeEntry.newStop)),
        ),
        action(
          'qa-saved-places',
          AppAssets.solarMapPoint,
          l10n.menuSavedPlaces,
          () => unawaited(
            _coverWith(
              () => Navigator.push<void>(
                context,
                RightToLeftTransition(SavedPlaces()),
              ),
            ),
          ),
        ),
        action(
          'qa-safety-kit',
          AppAssets.solarShieldCheck,
          l10n.safetyKit,
          () => unawaited(
            showRideSafetyKit(
              context,
              rideId: _match.ride.rideId,
              driverAssigned: false,
            ),
          ),
        ),
      ],
    );
  }
}
