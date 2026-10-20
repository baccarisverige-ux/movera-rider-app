import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_category_gate.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class ScheduleRide extends StatefulWidget {
  const ScheduleRide({super.key, this.editing});

  final Reservation? editing;

  /// What the Schedule map draws on top of the rider's blue location dot:
  /// nothing. CODE-4: a template marker labelled "Your location" sat at
  /// Stockholm Centralen for every rider.
  static const Set<Marker> mapMarkers = <Marker>{};

  @override
  State<ScheduleRide> createState() => _ScheduleRideState();
}

class _ScheduleRideState extends State<ScheduleRide> {
  static const Color _scheduleInk = Color(0xFF172127);
  // UI-6: was 0xFF7B858B (3.77:1 on white).
  static const Color _scheduleMuted = Color(0xFF6A7278);
  static const Color _scheduleSurface = Color(0xFFF5F6F6);
  static const Color _scheduleLine = Color(0xFFE4E7E8);
  static const Color _scheduleAccent = Color(0xFF356879);

  /// U5 stopgap (same kill-switch as Home's `_stopsSupported`): stops typed
  /// here reached `ScheduledRideSession.stops` → `SelectRide(stops:)` and were
  /// then silently dropped — `ReservationDraft` has no stops, and there is no
  /// multi-stop fare or routing. Hidden until multi-stop quoting, routing and
  /// booking exist end to end (blocked on backend).
  static const bool _stopsSupported = true;

  final TextEditingController _pickupController = TextEditingController(
    text: 'Current location',
  );
  final TextEditingController _dropoffController = TextEditingController();
  final List<TextEditingController> _stopControllers = [];

  // ignore: unused_field
  GoogleMapController? _mapController;
  final ScheduledRideSession _session = ScheduledRideSession();

  // Default location
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(59.3293, 18.0686), // neutral map fallback
    zoom: 14.0,
  );
  bool _nextInFlight = false;
  bool _mapParked = false;

  /// The pickup zone's time zone from its config, once read (Q9).
  String? _pickupTimeZone;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _pickupController.text = editing.pickup.label;
      _dropoffController.text = editing.destination.label;
      _session.captureSchedule(editing.scheduledPickupAt);
      _session.captureRideType(editing.categoryId);
      _session.capturePayment(editing.paymentMethod);
      if (editing.hasPreferences) _session.captureNote(editing.note!.trim());
    }
    setWebOverlayOpen(true);
    _pickupController.addListener(_syncRouteToSession);
    _dropoffController.addListener(_syncRouteToSession);
    _syncRouteToSession();
  }

  @override
  void dispose() {
    _pickupController.removeListener(_syncRouteToSession);
    _dropoffController.removeListener(_syncRouteToSession);
    _pickupController.dispose();
    _dropoffController.dispose();
    for (final controller in _stopControllers) {
      controller.removeListener(_syncRouteToSession);
      controller.dispose();
    }
    sc.dispose();
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.schedule);
    super.dispose();
  }

  int currentStep = 0;
  int? _tripMinutes;

  void _syncRouteToSession() {
    _session.captureRoute(
      pickup: _pickupController.text,
      dropoff: _dropoffController.text,
      stops: _stopControllers
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }

  Future<void> goToNextStep() async {
    if (_nextInFlight) return;
    _nextInFlight = true;
    setState(() {});
    try {
      FocusScope.of(context).unfocus();
      _syncRouteToSession();
      if (currentStep == 0) {
        await _confirmPickupThenCalendar();
        return;
      }
      if (currentStep >= 1) {
        await _withParkedScheduleMap(() {
          return openScheduledCategorySelector(
            context,
            session: _session,
            editingReservationId: widget.editing?.reservationId,
            initialRideId: widget.editing?.categoryId,
            initialPaymentMethod: widget.editing?.paymentMethod,
          );
        });
      }
    } finally {
      _nextInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _withParkedScheduleMap(
    Future<void> Function() action,
  ) async {
    final parkedNow = !_mapParked;
    if (parkedNow) {
      setState(() => _mapParked = true);
      AppScope.instance.maps.detach(owner: MapOwners.schedule);
      _mapController = null;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    try {
      await action();
    } finally {
      if (parkedNow && mounted) {
        setState(() => _mapParked = false);
      }
    }
  }

  Future<void> _confirmPickupThenCalendar() async {
    // Only the camera start for the pin screen: the rider confirms the real
    // spot there (CODE-5), so a missing fix just opens the default view.
    final start = await resolveScheduledPoint(_pickupController.text) ??
        _initialPosition.target;
    if (!mounted) return;
    final spot = await ConfirmPickupSpot.open(
      context,
      initialPosition: start,
      initialAddress: _pickupController.text.trim().isEmpty
          ? 'Current location'
          : _pickupController.text.trim(),
      confirmLabel: 'Confirm pickup spot',
    );
    if (spot == null || !mounted) return;
    // The drop-off must be a real place before choosing a time; its distance
    // gives the honest arrival estimate on the next screen.
    final dropoff = await findScheduledPoint(_dropoffController.text);
    if (!mounted) return;
    if (dropoff == null) {
      MoveraToast.show(context, 'Choose a valid destination address.');
      return;
    }
    _tripMinutes = estimatedTripMinutes(
      GeoPoint(spot.position.latitude, spot.position.longitude),
      GeoPoint(dropoff.latitude, dropoff.longitude),
    );
    _pickupController.text = spot.address;
    _session.capturePickupPoint(
      spot.position.latitude,
      spot.position.longitude,
      address: spot.address,
    );
    _syncRouteToSession();
    // Q9: the pickup zone's time zone, as its config names it.
    final timeZone = await AppScope.instance.riderConfig.timeZoneAt(
      spot.position.latitude,
      spot.position.longitude,
    );
    if (!mounted) return;
    setState(() {
      _pickupTimeZone = timeZone;
      currentStep = 1;
    });
  }

  void goToPreviousStep() {
    FocusScope.of(context).unfocus();
    if (currentStep == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => currentStep -= 1);
  }

  void _editRoute() {
    FocusScope.of(context).unfocus();
    if (currentStep == 0) return;
    setState(() => currentStep = 0);
  }

  void _addStop() {
    if (!_stopsSupported || _stopControllers.length >= 3) return;
    final controller = TextEditingController();
    controller.addListener(_syncRouteToSession);
    setState(() => _stopControllers.add(controller));
    _syncRouteToSession();
  }

  void _removeStop(int index) {
    final controller = _stopControllers.removeAt(index);
    controller.removeListener(_syncRouteToSession);
    controller.dispose();
    setState(() {});
    _syncRouteToSession();
  }

  ScrollController sc = ScrollController();

  Widget _buildPanelContent() {
    if (currentStep == 0) {
      return _buildAddressStep();
    }
    return ScheduleDateTimeSelector(
      onConfirm: goToNextStep,
      onBack: goToPreviousStep,
      body: body(),
      session: _session,
      tripMinutes: _tripMinutes,
      // Q9: the pickup zone's local time.
      timeZone:
          _pickupTimeZone ??
          PickupSchedule.at(_session.pickupLat, _session.pickupLng).timeZone,
    );
  }

  Widget _buildAddressStep() {
    final canContinue = _dropoffController.text.trim().isNotEmpty;
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Material(
                          color: _scheduleSurface,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: goToPreviousStep,
                            customBorder: const CircleBorder(),
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.arrow_back_rounded,
                                size: 23,
                                color: _scheduleInk,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'SCHEDULE',
                          style: GoogleFonts.poppins(
                            color: _scheduleMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Plan your ride',
                      style: GoogleFonts.poppins(
                        color: _scheduleInk,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Where should your Movera driver pick you up?',
                      style: GoogleFonts.poppins(
                        color: _scheduleMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _scheduleLine),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.045),
                            blurRadius: 22,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _scheduleAddressField(
                            controller: _pickupController,
                            label: 'Pickup',
                            hint: 'Enter pickup address',
                            icon: Icons.my_location_rounded,
                          ),
                          const Divider(height: 1, indent: 42),
                          if (_stopsSupported)
                            for (
                              var index = 0;
                              index < _stopControllers.length;
                              index++
                            ) ...[
                              _scheduleAddressField(
                                controller: _stopControllers[index],
                                label: 'Stop ${index + 1}',
                                hint: 'Enter stop address',
                                icon: Icons.more_horiz_rounded,
                                onRemove: () => _removeStop(index),
                              ),
                              const Divider(height: 1, indent: 42),
                            ],
                          _scheduleAddressField(
                            controller: _dropoffController,
                            label: 'Drop-off',
                            hint: 'Where to?',
                            icon: Icons.location_on_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    if (_stopsSupported && _stopControllers.length < 3)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addStop,
                          style: TextButton.styleFrom(
                            foregroundColor: _scheduleInk,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: Text(
                            'Add a stop',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 25),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _scheduleSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: _scheduleAccent,
                            size: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You will choose the date and time on the next screen.',
                              style: GoogleFonts.poppins(
                                color: _scheduleMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _scheduleLine)),
              ),
              child: SafeArea(
                top: false,
                child: PointerInterceptor(
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: canContinue && !_nextInFlight
                          ? goToNextStep
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _scheduleInk,
                        disabledBackgroundColor: _scheduleInk.withValues(
                          alpha: 0.18,
                        ),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        'Next',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _scheduleAddressField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    VoidCallback? onRemove,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Icon(icon, color: _scheduleAccent, size: 20),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            textInputAction: label == 'Drop-off'
                ? TextInputAction.done
                : TextInputAction.next,
            style: GoogleFonts.poppins(
              color: _scheduleInk,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              labelStyle: GoogleFonts.poppins(
                color: _scheduleMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
              hintStyle: GoogleFonts.poppins(
                color: _scheduleMuted.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            color: _scheduleMuted,
            iconSize: 18,
            tooltip: 'Remove stop',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goToPreviousStep();
      },
      child: PointerInterceptor(
        child: Scaffold(body: _buildPanelContent()),
      ),
    );
  }

  Widget verticleCircle({
    String? icon,
    bool isStop = false,
    String? stopText,
    bool removeDottedLine = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: ResSize.h * 32,
            width: ResSize.w * 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColor.liteBlue,
            ),
            child: Center(
              child: isStop
                  ? TextWidget(
                      text: stopText,
                      fontWeight: fwBold,
                      fontSize: 16,
                      color: AppColor.black,
                    )
                  : Image.asset(icon!, height: ResSize.h * 22),
            ),
          ),
          removeDottedLine
              ? 0.height
              : Expanded(
                  child: DottedLine(
                    dashLength: 3,
                    dashGapLength: 3,
                    lineThickness: 1.4,
                    dashColor: AppColor.black,
                    direction: Axis.vertical,
                  ),
                ),
        ],
      ),
    );
  }

  Widget horizentalLocation({String? title, location, bool isStop = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextWidget(
          fontSize: 12,
          fontWeight: fwSemiBold,
          text: title,
          color: Color(0xffA3A3A3),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: fwSemiBold,
                  color: AppColor.black,
                ),
              ),
            ),
            isStop
                ? Row(
                    children: [
                      10.width,
                      Image.asset(AppAssets.removeStop, height: ResSize.h * 24),
                    ],
                  )
                : SizedBox(),
          ],
        ),
      ],
    );
  }

  Widget body() {
    return SizedBox(
      child: Stack(
        children: [
          _mapParked
              ? const ColoredBox(color: Color(0xFFF5F6F6))
              : CustomGoogleMap(
            initialPosition: _initialPosition,
            markers: ScheduleRide.mapMarkers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // Green free-flow traffic hides the Waze road palette;
            // traffic stays on the active-trip map only.
            trafficEnabled: false,
            buildingsEnabled: true,
            indoorViewEnabled: false,
            mapType: MapType.normal,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              AppScope.instance.maps.attach(
                controller,
                owner: MapOwners.schedule,
              );
            },
            onTap: (LatLng position) {
              // Handle map tap events
            },
          ),
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
              child: Column(
                children: [
                  50.height,
                  Row(
                    children: [
                      InkWell(
                        onTap: goToPreviousStep,
                        child: Container(
                          height: ResSize.h * 24,
                          width: ResSize.w * 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColor.white,
                            boxShadow: [
                              BoxShadow(
                                offset: const Offset(0, 4),
                                color: Color(
                                  0xff606060,
                                  // ignore: deprecated_member_use
                                ).withValues(alpha: 0.12),
                                spreadRadius: 6,
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.arrow_back_ios_rounded,
                              color: AppColor.black,
                              size: ResSize.h * 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  18.height,
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppColor.white,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResSize.w * 16,
                        vertical: ResSize.h * 16,
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height:
                                    ResSize.h * 230, // more height to fit A & B
                                child: Column(
                                  children: [
                                    5.height,
                                    // Pickup Circle
                                    verticleCircle(icon: AppAssets.gps),

                                    2.height,
                                    verticleCircle(isStop: true, stopText: "A"),
                                    2.height,
                                    verticleCircle(isStop: true, stopText: "B"),
                                    2.height,
                                    verticleCircle(
                                      icon: AppAssets.location,
                                      removeDottedLine: true,
                                    ),
                                  ],
                                ),
                              ),
                              12.width,
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: _editRoute,
                                      child: horizentalLocation(
                                        title: "Pickup",
                                        location: _session.pickup,
                                      ),
                                    ),
                                    9.height,
                                    Divider(
                                      height: 0,
                                      thickness: 0.2,
                                      color: AppColor.border,
                                    ),
                                    9.height,

                                    horizentalLocation(
                                      title: "Stop 1",
                                      isStop: true,
                                      location: _session.stops.isNotEmpty
                                          ? _session.stops[0]
                                          : 'Not added',
                                    ),
                                    9.height,
                                    Divider(
                                      height: 0,
                                      thickness: 0.2,
                                      color: AppColor.border,
                                    ),
                                    9.height,

                                    horizentalLocation(
                                      isStop: true,
                                      title: "Stop 2",
                                      location: _session.stops.length > 1
                                          ? _session.stops[1]
                                          : 'Not added',
                                    ),
                                    9.height,
                                    Divider(
                                      height: 0,
                                      thickness: 0.2,
                                      color: AppColor.border,
                                    ),
                                    9.height,

                                    horizentalLocation(
                                      title: "Drop-off",
                                      location: _session.dropoff,
                                    ),
                                  ],
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
          ),
        ],
      ),
    );
  }
}
