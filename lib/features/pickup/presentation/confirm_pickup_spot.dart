import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/core/location/location_access_notice.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ConfirmPickupResult {
  const ConfirmPickupResult({required this.position, required this.address});
  final LatLng position;
  final String address;
}

class ConfirmPickupSpot extends StatefulWidget {
  const ConfirmPickupSpot({
    super.key,
    required this.initialPosition,
    required this.initialAddress,
    this.scheduledSummary,
    this.categoryName,
    this.title,
    this.hint,
    this.confirmLabel,
    this.positionIsFallback = false,
    this.refreshCurrentLocation = false,
  });

  static Future<ConfirmPickupResult?> open(
    BuildContext context, {
    required LatLng initialPosition,
    required String initialAddress,
    String? scheduledSummary,
    String? categoryName,
    String? title,
    String? hint,
    String? confirmLabel,
    bool positionIsFallback = false,
    bool refreshCurrentLocation = false,
  }) async {
    final route = RightToLeftTransition<ConfirmPickupResult>(
      ConfirmPickupSpot(
        initialPosition: initialPosition,
        initialAddress: initialAddress,
        scheduledSummary: scheduledSummary,
        categoryName: categoryName,
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        positionIsFallback: positionIsFallback,
        refreshCurrentLocation: refreshCurrentLocation,
      ),
      settings: const RouteSettings(name: AppRoutes.confirmPickup),
    );
    final result = await Navigator.of(context).push<ConfirmPickupResult>(route);
    await route.completed;
    return result;
  }

  final LatLng initialPosition;
  final String initialAddress;
  final String? scheduledSummary;
  final String? categoryName;
  final String? title;
  final String? hint;
  final String? confirmLabel;

  /// True when [initialPosition] is a default map point rather than a real
  /// fix or chosen place (U2 / D-002). Confirm stays disabled until the
  /// rider moves the pin, searches, or a real current location arrives.
  final bool positionIsFallback;

  /// D-011: the picker fetches its own fresh fix on open and recentres on it
  /// unless the rider has already moved the pin. Used when the initial
  /// position came from (possibly stale) GPS rather than a chosen place.
  final bool refreshCurrentLocation;

  /// Size of the centre pin glyph.
  static const pinSize = 44.0;

  /// Bottom padding that puts the tip of Icons.location_on (y ≈ 22/24 of the
  /// glyph box) exactly on the map centre (D-011: it sat ~4 px low).
  static const pinTipPadding = pinSize * 2 * (22 / 24) - pinSize;

  /// Screen radius in logical pixels of [meters] at [latitude] and [zoom]
  /// (Web Mercator, 256 px tiles).
  static double metersToPixels(double meters, double latitude, double zoom) {
    final metersPerPixel =
        156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);
    return meters / metersPerPixel;
  }

  @override
  State<ConfirmPickupSpot> createState() => _ConfirmPickupSpotState();
}

class _ConfirmPickupSpotState extends State<ConfirmPickupSpot> {
  GoogleMapController? _map;
  late LatLng _center;
  late String _address;
  bool _mapReady = false;
  bool _mapMountScheduled = false;
  bool _moving = false;
  bool _confirming = false;
  String? _pickupError;

  /// "Open settings" for a blocked permission or Location Services off.
  LocationSettingsOpener? _pickupSettings;
  bool _hasUsablePickupCoordinates = true;
  final ValueNotifier<double> _zoom = ValueNotifier<double>(16.4);
  final _search = TextEditingController();
  late final PickupMapController _pickup = PickupMapController(
    location: AppScope.instance.location,
    geocoding: AppScope.instance.geocoding,
  );

  static const _radiusMeters = 90.0;

  @override
  void initState() {
    super.initState();
    _center = widget.initialPosition;
    _address = widget.initialAddress;
    _hasUsablePickupCoordinates =
        widget.initialPosition.latitude.isFinite &&
        widget.initialPosition.longitude.isFinite &&
        widget.initialPosition.latitude >= -90 &&
        widget.initialPosition.latitude <= 90 &&
        widget.initialPosition.longitude >= -180 &&
        widget.initialPosition.longitude <= 180 &&
        !widget.positionIsFallback;
    _search.text = widget.initialAddress;
    setWebOverlayOpen(false);
    if (widget.refreshCurrentLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshCurrentFix());
      });
    }
  }

  /// D-011: take a fresh fix rather than trusting the position Home had.
  Future<void> _refreshCurrentFix() async {
    PickupCurrentPositionResult result;
    try {
      result = await _pickup.currentPosition().timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      return;
    }
    final position = result.position;
    // Never yank the pin away from a spot the rider already dragged to.
    if (!mounted || position == null || _isAwayFrom(widget.initialPosition)) {
      return;
    }
    setState(() {
      _center = position;
      _hasUsablePickupCoordinates = true;
      _address = 'Current location';
      _search.text = _address;
    });
    await _map?.animateCamera(CameraUpdate.newLatLng(position));
    final address = await _pickup.reverse(position);
    if (!mounted || _isAwayFrom(position) || isUnusablePickupLabel(address)) {
      return;
    }
    setState(() {
      _address = address!.trim();
      _search.text = _address;
    });
  }

  /// Whether the pin centre is more than ~15 m from [point].
  bool _isAwayFrom(LatLng point) =>
      (_center.latitude - point.latitude).abs() > 0.00015 ||
      (_center.longitude - point.longitude).abs() > 0.00015;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mapMountScheduled) return;
    _mapMountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_mountMapWhenRouteSettles());
    });
  }

  Future<void> _mountMapWhenRouteSettles() async {
    await waitForCurrentRouteToSettle(context);
    if (!mounted) return;
    setState(() => _mapReady = true);
  }

  @override
  void dispose() {
    _search.dispose();
    _zoom.dispose();
    _pickup.dispose();
    AppScope.instance.maps.detach(owner: MapOwners.pickup);
    super.dispose();
  }

  /// D-002: the rider moved the pin away from the fallback point.
  void _resolveFallbackIfMoved() {
    if (!widget.positionIsFallback || _hasUsablePickupCoordinates) return;
    if (_isAwayFrom(widget.initialPosition)) {
      _hasUsablePickupCoordinates = true;
    }
  }

  Future<void> _idle() async {
    if (_moving) return;
    final address = await _pickup.reverse(_center);
    if (!mounted) return;
    // D-010: a raw "lat, lng" string is not an address the rider can use.
    final label = isUnusablePickupLabel(address)
        ? pickupLocationFallbackLabel
        : address!.trim();
    setState(() {
      _address = label;
      _search.text = label;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _pickupError = null;
      _pickupSettings = null;
    });
    final at = _center;
    final result = await _pickup.currentPosition();
    if (!mounted) return;
    // rider-u134: the rider moved the pin while the fix was coming; a late
    // answer must not move it away from there.
    if (result.position != null && (_moving || _isAwayFrom(at))) return;
    final position = result.position;
    if (position == null) {
      setState(() {
        _pickupError = switch (result.failure) {
          PickupLocationFailure.servicesDisabled =>
            context.l10n.locServicesOff,
          PickupLocationFailure.permissionDenied =>
            context.l10n.locPermissionNeeded,
          PickupLocationFailure.permissionDeniedForever =>
            context.l10n.locPermissionBlocked,
          PickupLocationFailure.unavailable =>
            context.l10n.locUnavailableTryAgain,
          null => context.l10n.locUnavailable,
        };
        _pickupSettings = switch (result.failure) {
          PickupLocationFailure.servicesDisabled => locationSettingsOpenerFor(
            LocationAccessIssue.servicesOff,
          ),
          PickupLocationFailure.permissionDeniedForever =>
            locationSettingsOpenerFor(LocationAccessIssue.deniedForever),
          _ => null,
        };
      });
      return;
    }
    setState(() {
      _center = position;
      _hasUsablePickupCoordinates = true;
      _address = 'Current location';
      _search.text = _address;
    });
    await _map?.animateCamera(CameraUpdate.newLatLng(position));
    final address = await _pickup.reverse(position);
    if (!mounted || isUnusablePickupLabel(address)) return;
    setState(() {
      _address = address!.trim();
      _search.text = _address;
    });
  }

  Future<void> _lookup() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    final found = await _pickup.search(query);
    if (!mounted || found == null) return;
    setState(() {
      _center = found.position;
      _hasUsablePickupCoordinates = true;
      _address = found.address ?? query;
    });
    await _map?.animateCamera(CameraUpdate.newLatLng(_center));
  }

  void _confirmPosition() {
    if (_confirming) return;
    _confirming = true;
    final position = _center;
    final address = confirmedPickupAddress(_address, position);
    Navigator.pop(
      context,
      ConfirmPickupResult(position: position, address: address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_mapReady)
                  CustomGoogleMap(
                    initialPosition: CameraPosition(
                      target: _center,
                      zoom: 16.4,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    // The accuracy ring is a flat screen circle sized with
                    // flat-map maths; a tilted ground would not match it.
                    tiltWithZoom: false,
                    onMapCreated: (controller) {
                      _map = controller;
                      AppScope.instance.maps.attach(
                        controller,
                        owner: MapOwners.pickup,
                      );
                    },
                    onCameraMove: (position) {
                      _moving = true;
                      _center = position.target;
                      // D-011: the radius overlay follows zoom live; it is
                      // screen-centred like the pin, so it never lags.
                      _zoom.value = position.zoom;
                    },
                    onCameraIdle: () {
                      _moving = false;
                      setState(_resolveFallbackIfMoved);
                      _idle();
                    },
                  ),
                if (_mapReady)
                  IgnorePointer(
                    child: Center(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _zoom,
                        builder: (context, zoom, _) {
                          final radius = ConfirmPickupSpot.metersToPixels(
                            _radiusMeters,
                            _center.latitude,
                            zoom,
                          ).clamp(8.0, 600.0);
                          return Container(
                            key: const ValueKey('pickup-accuracy-overlay'),
                            width: radius * 2,
                            height: radius * 2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(
                                0xFF2D5878,
                              ).withValues(alpha: 0.12),
                              border: Border.all(
                                color: const Color(
                                  0xFF2D5878,
                                ).withValues(alpha: 0.35),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      key: ValueKey('pickup-pin'),
                      padding: EdgeInsets.only(
                        bottom: ConfirmPickupSpot.pinTipPadding,
                      ),
                      child: Icon(
                        Icons.location_on,
                        size: ConfirmPickupSpot.pinSize,
                        color: Color(0xFF11181D),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        MoveraIconButton.round(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onPressed: () => Navigator.pop(context),
                          label: context.l10n.back,
                          iconSize: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + inset),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? context.l10n.confirmPickupSpot,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D252C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.hint ?? context.l10n.dragMapToMovePin,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF5C656C),
                  ),
                ),
                if (widget.scheduledSummary != null ||
                    widget.categoryName != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    [
                      if (widget.scheduledSummary != null)
                        widget.scheduledSummary,
                      if (widget.categoryName != null) widget.categoryName,
                    ].join('  ·  '),
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1D252C),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onSubmitted: (_) => _lookup(),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchAddress,
                    suffixIcon: IconButton(
                      onPressed: _lookup,
                      icon: const Icon(Icons.search_rounded),
                      tooltip: context.l10n.searchAddress,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _useCurrentLocation,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(context.l10n.useCurrentLocation),
                ),
                if (_pickupError != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _pickupError!,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                  ),
                  if (_pickupSettings != null)
                    TextButton(
                      key: const ValueKey('pickup-open-settings'),
                      onPressed: () => _pickupSettings!(),
                      child: Text(context.l10n.openSettings),
                    ),
                ],
                if (widget.positionIsFallback &&
                    !_hasUsablePickupCoordinates) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.locOffBody,
                    key: const ValueKey('pickup-fallback-hint'),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: const Color(0xFF9A3412),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _address,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF5C656C),
                  ),
                ),
                const SizedBox(height: 16),
                PointerInterceptor(
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _hasUsablePickupCoordinates
                          ? _confirmPosition
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF11181D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        widget.confirmLabel ?? context.l10n.confirmPickup,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
