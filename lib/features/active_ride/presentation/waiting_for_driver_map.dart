part of 'waiting_for_driver.dart';

class _WaitingRideMap extends StatefulWidget {
  const _WaitingRideMap({
    super.key,
    required this.initialPosition,
    required this.pickupPosition,
    required this.destinationPosition,
    required this.pickupAddress,
    required this.destinationAddress,
    this.stops = const <RouteStop>[],
    required this.tracking,
    this.cameraBottomPadding = 140,
    this.onTripRoute,
  });

  final CameraPosition initialPosition;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final String pickupAddress;
  final String destinationAddress;
  final List<RouteStop> stops;
  final DriverTrackingController tracking;

  /// Approximates the sheet's on-screen clearance so [fitBounds] doesn't
  /// frame the driver and target only to have the bottom sheet cover them.
  final double cameraBottomPadding;

  /// The real road route of the trip, once the map has it (Ride check
  /// measures "off the route" against it).
  final ValueChanged<List<GeoPoint>>? onTripRoute;

  @override
  State<_WaitingRideMap> createState() => _WaitingRideMapState();
}

/// G5 live test: the "1 min" ETA bubble over the pickup is the driver's
/// way there; once the driver has arrived it is gone (the plain pickup pin).
@visibleForTesting
bool pickupEtaPinShown(RideStatus status) => status != RideStatus.driverWaiting;

class _WaitingRideMapState extends State<_WaitingRideMap>
    with SingleTickerProviderStateMixin {
  // U7: the markers live in a notifier so the moving driver only updates the
  // map's marker set. It used to setState + drop the cached map leaf on
  // every animation tick, rebuilding the whole map subtree each frame.
  final ValueNotifier<Set<Marker>> _markerSet = ValueNotifier<Set<Marker>>(
    const <Marker>{},
  );
  Set<Marker> get _markers => _markerSet.value;
  set _markers(Set<Marker> next) => _markerSet.value = next;
  Set<Polyline> _polylines = const <Polyline>{};

  /// Green pickup pin (the rider waits there).
  BitmapDescriptor? _riderPuck;
  BitmapDescriptor? _destinationPin;
  BitmapDescriptor? _driverCar;
  // Pins that carry times: "N min" over the pickup, "Arrive by HH:MM" over
  // the destination. Rebuilt only when the minute changes.
  BitmapDescriptor? _pickupTimePin;
  bool _etaPinShown = true;
  BitmapDescriptor? _destinationTimePin;
  String? _timePinKey;
  DateTime? _lastPaint;
  Timer? _pendingRepaint;
  DateTime? _lastRouteRefresh;
  bool _mapReady = false;
  String? _routeKey;
  Widget? _leaf;
  bool _approximateRoute = false;

  /// G25 step A: kept mounted under a covering screen (native). No camera
  /// fit (it would move the covering screen's map), no marker easing, no
  /// route reads until [resumeAfterPark].
  bool _paused = false;
  GoogleMapController? _controller;

  void pauseWhileParked() {
    _paused = true;
    _pendingRepaint?.cancel();
    _driverAnim.stop();
  }

  /// Shown again: take the map back and catch up with the live trip.
  void resumeAfterPark() {
    if (!_paused) return;
    _paused = false;
    final controller = _controller;
    if (controller != null) {
      AppScope.instance.maps.attach(controller, owner: MapOwners.waiting);
    }
    _lastFitDriverPoint = null;
    _lastPaint = null;
    paintIfDue();
    if (_mapReady) unawaited(_refreshRoadRoute(force: true));
  }

  // M-01/M-02: the driver marker used to teleport to each new fix. Ease
  // between the last displayed position/heading and the new one instead.
  //
  // D-016: the ease used to be a fixed 900 ms while fixes arrive every ~2–3 s,
  // so the car moved for under a second and then stood still. The duration
  // now follows the observed interval between fixes (see driverEaseDuration).
  late final AnimationController _driverAnim =
      AnimationController(vsync: this, duration: driverEaseDuration(null))
        ..addListener(() {
          if (!mounted) return;
          // The ease now spans most of each fix interval, so cap marker updates
          // at ~20 fps rather than on every frame for that whole time.
          final now = DateTime.now();
          final last = _lastAnimRebuild;
          if (_driverAnim.isAnimating &&
              last != null &&
              now.difference(last) < const Duration(milliseconds: 50)) {
            return;
          }
          _lastAnimRebuild = now;
          // U7: markers only; the map leaf and the rest of the stack stay put.
          _markers = _buildMarkers();
        });
  DateTime? _lastAnimRebuild;
  DateTime? _lastFixArrivedAt;
  LatLng? _driverAnimFrom;
  LatLng? _driverAnimTo;
  double _driverHeadingFrom = 0;
  double _driverHeadingTo = 0;

  // M-08: last point the camera was fit to, so a fix that hasn't moved the
  // driver meaningfully doesn't re-trigger animateCamera every paint.
  LatLng? _lastFitDriverPoint;
  bool _lastFitInTrip = false;

  bool get _inTrip => DriverEta.isInTrip(widget.tracking.status);

  @override
  void initState() {
    super.initState();
    // rider-u59: a map rebuilt mid-ride (after a route change) starts from
    // the driver's last known fix instead of waiting for the next one,
    // which a driver standing at the pickup may not send for a while.
    _updateDriverAnimation();
    _markers = _buildMarkers();
    unawaited(_prepareMapVisuals());
  }

  @override
  void didUpdateWidget(covariant _WaitingRideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.cameraBottomPadding - widget.cameraBottomPadding).abs() >
        1) {
      // The sheet came to rest at another stop: reframe gently so the
      // driver and the pickup stay above it.
      _lastFitDriverPoint = null;
      if (_mapReady) _maybeFitCamera();
    }
    if (oldWidget.pickupPosition == widget.pickupPosition &&
        oldWidget.destinationPosition == widget.destinationPosition &&
        oldWidget.pickupAddress == widget.pickupAddress &&
        oldWidget.destinationAddress == widget.destinationAddress &&
        _sameStops(oldWidget.stops, widget.stops) &&
        identical(oldWidget.tracking, widget.tracking)) {
      return;
    }
    _markers = _buildMarkers();
    _polylines = const <Polyline>{};
    _routeKey = null;
    _leaf = null;
    if (_mapReady) {
      unawaited(_refreshRoadRoute(force: true));
    }
  }

  @override
  void dispose() {
    _pendingRepaint?.cancel();
    _driverAnim.dispose();
    _markerSet.dispose();
    super.dispose();
  }

  void paintIfDue() {
    if (_paused) return;
    final now = DateTime.now();
    if (_lastPaint != null &&
        now.difference(_lastPaint!) < const Duration(milliseconds: 400)) {
      // M-03: a fix arriving inside the throttle window used to be dropped
      // until the next unrelated event happened to call paintIfDue again.
      // Schedule one for the remainder of this window instead.
      final remaining =
          const Duration(milliseconds: 400) - now.difference(_lastPaint!);
      _pendingRepaint?.cancel();
      _pendingRepaint = Timer(remaining, () {
        if (mounted) paintIfDue();
      });
      return;
    }
    _lastPaint = now;
    _updateDriverAnimation();
    _syncTimePins();

    final next = _buildMarkers();
    // The pickup pin's look changes on arrival, not its place.
    final pinShown = pickupEtaPinShown(widget.tracking.status);
    final pinChanged = pinShown != _etaPinShown;
    _etaPinShown = pinShown;
    final markersChanged = pinChanged || !_sameMarkers(_markers, next);
    if (markersChanged && mounted) {
      // U7: no setState, no new map leaf; the marker listener updates it.
      _markers = next;
    }
    _maybeFitCamera();

    if (_mapReady &&
        (_lastRouteRefresh == null ||
            now.difference(_lastRouteRefresh!) >=
                const Duration(seconds: 10))) {
      unawaited(_refreshRoadRoute());
    }
  }

  /// Feeds a new fix into the from/to pair the animation eases between.
  /// The very first fix snaps (there is nothing to ease from yet).
  void _updateDriverAnimation() {
    final eta = widget.tracking.eta;
    final lat = eta?.latitude;
    final lng = eta?.longitude;
    if (lat == null || lng == null) return;
    final next = LatLng(lat, lng);
    final previousTo = _driverAnimTo;
    if (previousTo != null &&
        previousTo.latitude == next.latitude &&
        previousTo.longitude == next.longitude) {
      return;
    }
    final arrivedAt = DateTime.now();
    final previousArrival = _lastFixArrivedAt;
    _lastFixArrivedAt = arrivedAt;
    if (previousTo == null) {
      // First fix: nothing to animate from.
      _driverAnimFrom = next;
      _driverAnimTo = next;
      _driverHeadingFrom = 0;
      _driverHeadingTo = 0;
      return;
    }
    if (!driverMarkerEases) {
      // rider-u58: one marker update per fix, no in-between positions.
      final heading = _bearingDegrees(previousTo, next) ?? _driverHeadingTo;
      _driverAnim.stop();
      _driverAnimFrom = next;
      _driverAnimTo = next;
      _driverHeadingFrom = heading;
      _driverHeadingTo = heading;
      return;
    }
    _driverAnimFrom = _currentDriverPosition() ?? previousTo;
    _driverAnimTo = next;
    _driverHeadingFrom = _currentDriverHeading();
    _driverHeadingTo = _bearingDegrees(previousTo, next) ?? _driverHeadingFrom;
    _driverAnim
      ..stop()
      ..duration = driverEaseDuration(
        previousArrival == null ? null : arrivedAt.difference(previousArrival),
      )
      ..forward(from: 0);
  }

  LatLng? _currentDriverPosition() {
    final from = _driverAnimFrom;
    final to = _driverAnimTo;
    if (from == null || to == null) return to;
    final t = _driverAnim.value;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  double _currentDriverHeading() {
    if (_driverAnimFrom == null) return _driverHeadingTo;
    return lerpHeading(_driverHeadingFrom, _driverHeadingTo, _driverAnim.value);
  }

  /// Initial bearing from [from] to [to] in degrees, or null when the two
  /// points coincide (no direction to point).
  double? _bearingDegrees(LatLng from, LatLng to) {
    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return null;
    }
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return normalizeHeading(math.atan2(y, x) * 180 / math.pi);
  }

  void _maybeFitCamera() {
    if (_paused) return;
    final driver = _currentDriverPosition();
    if (driver == null) return;
    final target = _inTrip ? widget.destinationPosition : widget.pickupPosition;
    final samePoint =
        _lastFitDriverPoint != null &&
        _lastFitInTrip == _inTrip &&
        _lastFitDriverPoint!.latitude == driver.latitude &&
        _lastFitDriverPoint!.longitude == driver.longitude;
    if (samePoint) return;
    _lastFitDriverPoint = driver;
    _lastFitInTrip = _inTrip;
    // D-018: the sheet's clearance used to be passed as fitBounds' uniform
    // padding, i.e. applied to all four sides, which zoomed far out. Reserve
    // it at the bottom only by extending the framed bounds southwards.
    final fit = waitingCameraFit(
      a: GeoPoint(driver.latitude, driver.longitude),
      b: GeoPoint(target.latitude, target.longitude),
      viewportHeight: MediaQuery.maybeSizeOf(context)?.height ?? 800,
      bottomObstruction: widget.cameraBottomPadding,
    );
    unawaited(
      // A follow update: it leaves a map the rider is holding or has just
      // moved alone (the camera never moves under a finger).
      AppScope.instance.maps.fitBounds(
        fit.southwest,
        fit.northeast,
        padding: fit.padding,
        follow: true,
      ),
    );
  }

  bool _sameMarkers(Set<Marker> current, Set<Marker> next) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    final byId = <String, LatLng>{
      for (final marker in current) marker.markerId.value: marker.position,
    };
    for (final marker in next) {
      final position = byId[marker.markerId.value];
      if (position == null || position != marker.position) return false;
    }
    return true;
  }

  /// Labels for the time pins from the live ETA; new icons only when the
  /// label changes (minute granularity), never on every animation tick.
  void _syncTimePins() {
    final seconds = widget.tracking.eta?.seconds;
    if (seconds == null) return;
    final inTrip = _inTrip;
    final now = DateTime.now();
    final toPickupMin = (seconds / 60).ceil().clamp(1, 999);
    final arrive = inTrip
        ? now.add(Duration(seconds: seconds))
        : now.add(
            Duration(
              minutes:
                  toPickupMin +
                  estimatedRouteMinutes(
                    GeoPoint(
                      widget.pickupPosition.latitude,
                      widget.pickupPosition.longitude,
                    ),
                    [
                      for (final stop in widget.stops)
                        GeoPoint(stop.latitude, stop.longitude),
                    ],
                    GeoPoint(
                      widget.destinationPosition.latitude,
                      widget.destinationPosition.longitude,
                    ),
                  ),
            ),
          );
    final pickupLabel = context.l10n.minLineBreak('$toPickupMin');
    final arriveLabel = context.l10n.arriveBy(clockTime(arrive));
    final shown = pickupEtaPinShown(widget.tracking.status);
    final key = '$inTrip|$shown|$pickupLabel|$arriveLabel';
    if (key == _timePinKey) return;
    _timePinKey = key;
    unawaited(() async {
      final pins = await Future.wait([
        RouteTimeMarker.createIcon(pickup: true, label: pickupLabel),
        RouteTimeMarker.createIcon(pickup: false, label: arriveLabel),
      ]);
      if (!mounted || key != _timePinKey) return;
      _pickupTimePin = pins[0];
      _destinationTimePin = pins[1];
      _markers = _buildMarkers();
    }());
  }

  static bool _sameStops(List<RouteStop> a, List<RouteStop> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Set<Marker> _buildMarkers() {
    final driverPosition = _currentDriverPosition();
    final timePin = pickupEtaPinShown(widget.tracking.status)
        ? _pickupTimePin
        : null;
    final pickupIcon = timePin ?? _riderPuck;
    final destinationIcon = _destinationTimePin ?? _destinationPin;
    return {
      if (!_inTrip && pickupIcon != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickupPosition,
          infoWindow: InfoWindow(title: shortPickupPlace(widget.pickupAddress)),
          icon: pickupIcon,
          anchor: timePin != null
              ? RouteTimeMarker.anchor
              : const Offset(0.5, 0.5),
        ),
      ...routeStopMarkers(widget.stops),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationPosition,
        infoWindow: InfoWindow(
          title: shortPickupPlace(widget.destinationAddress),
        ),
        icon:
            destinationIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: _destinationTimePin != null
            ? RouteTimeMarker.anchor
            : const Offset(0.5, 0.5),
      ),
      if (driverPosition != null) _driverMarker(driverPosition),
    };
  }

  /// rider-u61: on the web the car bitmap comes turned (the plugin ignores
  /// rotation there).
  Marker _driverMarker(LatLng position) {
    final look = MoveraVehicleMarker.look(
      _driverCar,
      _currentDriverHeading(),
      onReady: () {
        if (mounted) setState(() {});
      },
    );
    return Marker(
      markerId: const MarkerId('driver'),
      position: position,
      rotation: look.rotation,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon:
          look.icon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
    );
  }

  Future<void> _prepareMapVisuals() async {
    final icons = await Future.wait<BitmapDescriptor>([
      RouteEndpointMarker.createIcon(pickup: true),
      MoveraVehicleMarker.createIcon(),
      RouteEndpointMarker.createIcon(pickup: false),
    ]);
    if (!mounted) return;
    setState(() {
      _riderPuck = icons[0];
      _destinationPin = icons[2];
      _driverCar = icons[1];
      _markers = _buildMarkers();
      _leaf = null;
    });
  }

  /// rider-u62/u63: how many of the trip's stops, in order, the car has
  /// reached (come within [_stopReachedMeters] of). The route from the
  /// driver goes through the rest.
  int _stopsReached = 0;
  static const double _stopReachedMeters = 80;

  void _noteStopsReached(GeoPoint driverPoint) {
    final stops = widget.stops;
    var reached = _stopsReached;
    while (reached < stops.length) {
      final stop = stops[reached];
      final meters = GeoDistance.metersBetween(
        driverPoint.latitude,
        driverPoint.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (meters > _stopReachedMeters) break;
      reached += 1;
    }
    if (reached != _stopsReached) {
      _stopsReached = reached;
      _routeKey = null; // The next refresh draws the remaining legs.
    }
  }

  /// The stops still ahead of the car, in order.
  List<GeoPoint> _remainingStops() {
    final stops = widget.stops;
    final reached = _stopsReached.clamp(0, stops.length);
    return [
      for (final stop in stops.sublist(reached))
        GeoPoint(stop.latitude, stop.longitude),
    ];
  }

  ({GeoPoint from, List<GeoPoint> via, GeoPoint to})? _routeEndpoints() {
    final eta = widget.tracking.eta;
    final driverPoint = eta?.latitude != null && eta?.longitude != null
        ? GeoPoint(eta!.latitude!, eta.longitude!)
        : null;

    if (_inTrip) {
      if (driverPoint != null) _noteStopsReached(driverPoint);
      return (
        from:
            driverPoint ??
            GeoPoint(
              widget.pickupPosition.latitude,
              widget.pickupPosition.longitude,
            ),
        // rider-u62/u63: through the stops still ahead, never straight to
        // the destination past them.
        via: _remainingStops(),
        to: GeoPoint(
          widget.destinationPosition.latitude,
          widget.destinationPosition.longitude,
        ),
      );
    }

    if (driverPoint == null) return null;
    return (
      from: driverPoint,
      via: const <GeoPoint>[],
      to: GeoPoint(
        widget.pickupPosition.latitude,
        widget.pickupPosition.longitude,
      ),
    );
  }

  Future<void> _refreshRoadRoute({bool force = false}) async {
    if (!_mapReady || _paused) return;
    final endpoints = _routeEndpoints();
    if (endpoints == null) return;

    String keyFor(GeoPoint point) =>
        '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    final requestKey =
        '${_inTrip ? 'trip' : 'pickup'}:${keyFor(endpoints.from)}>'
        '${endpoints.via.map(keyFor).join('>')}>${keyFor(endpoints.to)}';
    if (!force && requestKey == _routeKey) return;

    _routeKey = requestKey;
    _lastRouteRefresh = DateTime.now();
    final resolved = await roadRoutePolylineVia(
      id: 'active-road-route',
      from: LatLng(endpoints.from.latitude, endpoints.from.longitude),
      via: [
        for (final stop in endpoints.via) LatLng(stop.latitude, stop.longitude),
      ],
      to: LatLng(endpoints.to.latitude, endpoints.to.longitude),
      color: RiderRouteStyle.color,
    );
    final route = resolved.route;
    if (!mounted || _routeKey != requestKey || route.points.length < 2) return;

    // A leg falls back to a straight two-point line whenever a real road
    // route can't be resolved. A genuine road route for anything but a
    // trivially short hop has more than two vertices, so this is a
    // reasonable signal to tell the rider the line is approximate rather
    // than implying turn-by-turn accuracy that isn't there.
    final approximate = resolved.approximate;
    if (_inTrip && !approximate) {
      widget.onTripRoute?.call([
        for (final point in route.points)
          GeoPoint(point.latitude, point.longitude),
      ]);
    }
    setState(() {
      _polylines = styledRoute(route);
      _approximateRoute = approximate;
      _leaf = null;
    });
  }

  Widget _buildMap(Set<Marker> markers) {
    return CustomGoogleMap(
      key: const ValueKey('waiting-map'),
      // Owner, live test 2026-10-26 (N6): the booking and trip maps stay
      // flat; the route is read from above, never along a tilted horizon.
      tiltWithZoom: false,
      initialPosition: widget.initialPosition,
      markers: markers,
      polylines: _polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false,
      mapType: MapType.normal,
      onMapCreated: (controller) {
        _mapReady = true;
        _controller = controller;
        AppScope.instance.maps.attach(controller, owner: MapOwners.waiting);
        unawaited(_refreshRoadRoute(force: true));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _leaf ??= RepaintBoundary(
            child: ValueListenableBuilder<Set<Marker>>(
              valueListenable: _markerSet,
              builder: (context, markers, _) => _buildMap(markers),
            ),
          ),
        ),
        if (_approximateRoute)
          Positioned(
            left: 12,
            bottom: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  context.l10n.approximateRoute,
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
