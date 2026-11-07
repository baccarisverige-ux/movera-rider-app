part of 'home.dart';

extension _HomeMapControls on _HomeState {
  /// Owner 2026-10-31 (rider-pin SPEC): the flat pin, and the tilted pucks
  /// when the pin leans with the camera
  /// ([MoveraRiderPuckMarker.tiltsWithCamera]), all at the screen's pixel
  /// ratio so they are sharp.
  Future<void> _prepareLocationPuckIcons() async {
    // Read from the platform, not the widget tree: this also runs from
    // initState's first-fix path.
    final ratio =
        WidgetsBinding
            .instance
            .platformDispatcher
            .implicitView
            ?.devicePixelRatio ??
        markerPixelRatio;
    if (_pins[0] == null) {
      _pins[0] ??= await _HomeState._drawPin(0, ratio);
    }
    if (_halo == null) {
      final halo = await RiderAccuracyHalo.createVisual(pixelRatio: ratio);
      halo.image.dispose();
      _halo ??= halo.icon;
    }
    if (_tiltPinsStarted || !MoveraRiderPuckMarker.tiltsWithCamera) return;
    _tiltPinsStarted = true;
    unawaited(() async {
      for (
        var tilt = MoveraRiderPuckMarker.tiltStep;
        tilt <= 70;
        tilt += MoveraRiderPuckMarker.tiltStep
      ) {
        _pins[tilt] = await _HomeState._drawPin(tilt, ratio);
      }
      // A tilted camera got the flat pin while the pucks were drawn.
      if (mounted && _paintedPinBucket != _pinBucket) {
        _updateLocationVisuals();
      }
    }());
  }

  /// The pin bitmap the camera's tilt asks for.
  int get _pinBucket => MoveraRiderPuckMarker.tiltsWithCamera
      ? MoveraRiderPuckMarker.tiltBucket(_locationCtl.lastMapTilt)
      : 0;

  Future<bool> _startHeadingTracking({bool fromTap = false}) {
    return _locationCtl.startHeading(
      fromTap: fromTap,
      isMounted: () => mounted,
      onHeading: (heading) {
        _locationHeading = heading;
        _hasCompassHeading = true;
        _updateLocationVisuals();
      },
    );
  }

  /// North-up, like the driver app's Home locate: the map does not turn
  /// with the compass; the puck shows the heading.
  Future<void> _flyToUser(LatLng target, {required bool follow}) {
    return AppScope.instance.maps.animateCamera(
      GeoPoint(target.latitude, target.longitude),
      zoom: recenterZoom,
      bearing: 0,
      follow: follow,
    );
  }

  void _loadMarkers() {
    _locationCtl.clearOverlays();
  }

  /// Room the promotion ticket takes at the low and middle snaps.
  double get _promotionExtra =>
      _promotion == null ? 0 : PromotionTicket.height + ResSize.h * 10;

  double get _sheetMinPixels =>
      ResSize.h * _HomeState._sheetMinHeight + _promotionExtra;

  double get _sheetMidPixels =>
      ResSize.h * _HomeState._sheetMaxHeight + _promotionExtra;

  bool get _isSheetAtMiddle => _sheetCtl.isAtMiddle;

  void _cancelSheetIdleTimer() => _sheetCtl.cancelIdleTimer();

  void _scheduleSheetIdleClose() {
    _sheetCtl.scheduleIdleClose(
      accessibleNavigation:
          MediaQuery.maybeOf(context)?.accessibleNavigation ?? false,
      isMounted: () => mounted,
    );
  }

  /// Owner round 1: the web map ignores pointers while the sheet covers it.
  /// Told once the sheet settles, not on every drag offset (each call
  /// reaches the platform view and could nudge the map mid-drag); the
  /// sheet itself never lets a pointer through to the map meanwhile.
  void _syncWebOverlay(double offset) {
    if (_mapParked.value) return;
    final covering = offset > _sheetMinPixels + 12;
    if (covering == _webOverlayCovering) return;
    _webOverlayCovering = covering;
    setWebOverlayOpen(covering);
  }

  Future<void> _animateHomeSheetTo(
    SheetOffset target, {
    Duration duration = MoveraDurations.large,
    Curve curve = MoveraCurves.open,
  }) => _sheetCtl.animateTo(target, duration: duration, curve: curve);

  /// Opens a bottom-bar tab over Home. A horizontal swipe on that page
  /// hands back the neighbouring tab's index, so the rider can slide
  /// Home → Payment → Account and back without tapping. Schedule ride is a
  /// booking flow, not a page, so the swipe skips it (NAV-5).
  void _openTab(int first) {
    unawaited(
      _runRouteFlow(
        () => _withParkedHomeMap<void>(() async {
          var current = HomeTabs.home;
          int? next = first;
          while (next != null && next != HomeTabs.home && mounted) {
            final forward = next > current;
            current = next;
            final page = HomeTabPage(
              tab: next,
              child: next == HomeTabs.payment
                  ? walletAndPaymentsScreen(initialTab: 1)
                  : const AccountHomePage(),
            );
            next = await Navigator.of(context).push<int>(
              forward
                  ? RightToLeftTransition(page)
                  : LeftToRightTransition(page),
            );
          }
        }),
      ),
    );
  }

  /// Owner round 3: how far the map rises with the sheet: a third of the
  /// sheet's rise above its low stop, at most a quarter of the map.
  double _mapLift(double mapHeight) {
    if (!_homeSheetController.hasClient) return 0;
    final offset = _homeSheetController.metrics?.offset;
    if (offset == null || !offset.isFinite) return 0;
    final rise = offset - _sheetMinPixels;
    if (rise <= 0) return 0;
    return (rise / 3).clamp(0.0, mapHeight / 4);
  }

  /// Owner round 1: the map's height is read once per layout (a new width:
  /// a rotation, a resized window), not per frame. Within one layout it
  /// keeps the tallest height seen, so a viewport that shrinks and grows
  /// again for a moment (a mobile browser's bars during a sheet drag) never
  /// resizes the map, and the map never moves under the rider's finger.
  /// The part below a shorter viewport is simply clipped.
  double _stableMapHeight(Size viewport) {
    final last = _mapLayout;
    if (last == null ||
        last.width != viewport.width ||
        viewport.height > last.height) {
      _mapLayout = viewport;
    }
    return _mapLayout!.height;
  }
}
