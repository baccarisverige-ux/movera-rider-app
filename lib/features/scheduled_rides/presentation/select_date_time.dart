import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';

class ScheduleDateTimeSelector extends StatefulWidget {
  /// The next step. Continue stays locked until it completes (rider-88).
  final FutureOr<void> Function() onConfirm;
  final VoidCallback? onBack;
  final Widget body;
  final ScheduledRideSession? session;
  final bool popOnConfirm;
  final DateTime Function()? now;

  /// Trip length for the "Estimated arrival / pickup" row. Unknown (null)
  /// hides the row rather than showing a made-up time, and Arrive by is
  /// not offered: without it there is no pickup to book (rider-89).
  final int? tripMinutes;

  /// Q9: the pickup zone's IANA time zone; every time on this screen is
  /// that zone's wall-clock time.
  final String timeZone;

  /// rider-r4-10: how many days ahead the zone takes reservations
  /// (`booking.bookingHorizonDays` of its config).
  final int horizonDays;

  const ScheduleDateTimeSelector({
    super.key,
    required this.body,
    required this.onConfirm,
    this.onBack,
    this.session,
    this.popOnConfirm = false,
    this.now,
    this.tripMinutes,
    this.timeZone = ZoneClock.stockholm,
    this.horizonDays = RiderAppConfig.defaultBookingHorizonDays,
  });

  /// Same "When should we pick you up?" screen, used when Book now
  /// switches to Book for later on the category cards.
  static Future<DateTime?> choose(
    BuildContext context, {
    DateTime? initial,
    DateTime Function()? now,
    int? tripMinutes,
    String timeZone = ZoneClock.stockholm,
    int horizonDays = RiderAppConfig.defaultBookingHorizonDays,
  }) {
    // rider-u225: the prefill goes in as it is; initState clamps it and
    // says so when it moved (captureSchedule would clamp it silently).
    final session = ScheduledRideSession()
      ..scheduledAt = initial
      ..timezone = timeZone;
    return Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          session: session,
          popOnConfirm: true,
          now: now,
          tripMinutes: tripMinutes,
          timeZone: timeZone,
          horizonDays: horizonDays,
          onConfirm: () {},
        ),
      ),
    );
  }

  @override
  State<ScheduleDateTimeSelector> createState() =>
      _ScheduleDateTimeSelectorState();
}

class _ScheduleDateTimeSelectorState extends State<ScheduleDateTimeSelector> {
  static const Color _ink = Color(0xFF15191C);
  // UI-6: was 0xFF7B8287 (3.90:1 on white).
  static const Color _muted = Color(0xFF6B7176);
  static const Color _surface = Color(0xFFF5F5F3);
  static const Color _line = Color(0xFFE7E7E4);

  late final PickupSchedule _schedule = PickupSchedule(widget.timeZone);
  late DateTime _selectedDateTime;
  bool _pickupMode = true;
  bool _continuing = false;
  String? _pickupCorrectionMessage;

  @override
  void initState() {
    super.initState();
    setWebOverlayOpen(true);
    final existing = widget.session?.scheduledAt;
    final now = widget.now?.call();
    if (existing != null) {
      final corrected = _withinHorizon(_schedule.clampPickup(existing, now));
      _selectedDateTime = corrected;
      if (corrected != existing) {
        _pickupCorrectionMessage = _beyondHorizon(existing, now)
            ? context.l10n.pickupTimeWithinHorizon(widget.horizonDays)
            : context.l10n.pickupTimeUpdated;
      }
    } else {
      _selectedDateTime = _schedule.defaultPickup(now);
    }
    _commitSchedule();
  }

  @override
  void dispose() {
    setWebOverlayOpen(false);
    super.dispose();
  }

  /// rider-89: in Arrive by the chosen time is the arrival, and the pickup
  /// booked is that minus the trip estimate, on the slot at or before it so
  /// the rider is not late. Otherwise the chosen time is the pickup.
  DateTime _pickupFor(DateTime chosen) {
    final trip = widget.tripMinutes;
    if (_pickupMode || trip == null) return chosen;
    // The trip is real elapsed time in the pickup zone, not the device
    // zone, and the booking reads a repeated hour as its later copy: step
    // back a slot until the booked instant is not after arrival - trip.
    final latest = _schedule
        .toUtc(chosen)
        .subtract(Duration(minutes: trip));
    final wall = ZoneClock.wallTime(widget.timeZone, latest);
    var slot = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute - wall.minute % StockholmSchedule.slotMinutes,
    );
    DateTime plain(DateTime f) =>
        DateTime(f.year, f.month, f.day, f.hour, f.minute);
    while (_schedule.toUtc(plain(slot)).isAfter(latest)) {
      slot = slot.subtract(
        const Duration(minutes: StockholmSchedule.slotMinutes),
      );
    }
    return plain(slot);
  }

  DateTime get _pickupAt => _pickupFor(_selectedDateTime);

  /// rider-r4-10: the latest pickup the zone takes (its horizon from now).
  DateTime _latestPickup([DateTime? now]) =>
      _schedule.latestPickup(widget.horizonDays, now ?? widget.now?.call());

  bool _beyondHorizon(DateTime chosen, [DateTime? now]) =>
      chosen.isAfter(_latestPickup(now));

  DateTime _withinHorizon(DateTime chosen, [DateTime? now]) =>
      _beyondHorizon(chosen, now) ? _latestPickup(now) : chosen;

  /// [chosen] on the slot grid, raised to the first time whose pickup is
  /// legal.
  DateTime _clampChosen(DateTime chosen, DateTime? now) {
    final trip = widget.tripMinutes;
    if (_pickupMode || trip == null) {
      return _withinHorizon(_schedule.clampPickup(chosen, now), now);
    }
    if (_schedule.isLegalPickup(_pickupFor(chosen), now)) {
      final arrival = StockholmSchedule.roundToFive(chosen);
      return _beyondHorizon(_pickupFor(arrival), now)
          ? _latestPickup(now)
          : arrival;
    }
    final first = _schedule.minimumPickup(now);
    return StockholmSchedule.roundToFive(
      DateTime(first.year, first.month, first.day, first.hour, first.minute + trip),
    );
  }

  Future<void> _goNext() async {
    if (_continuing) return;

    final now = widget.now?.call();
    if (!_schedule.isLegalPickup(_pickupAt, now)) {
      final corrected = _clampChosen(_selectedDateTime, now);
      setState(() {
        _selectedDateTime = corrected;
        _pickupCorrectionMessage =
            context.l10n.pickupTimeUpdated;
      });
      _commitSchedule();
      return;
    }

    _continuing = true;
    _pickupCorrectionMessage = null;
    _commitSchedule();

    if (widget.popOnConfirm) {
      Navigator.pop(context, _pickupAt);
      return;
    }

    setState(() {});
    try {
      await widget.onConfirm();
    } finally {
      // rider-88: the rider can come back from the next step (or it can
      // stop early with a toast) to this same State; Continue works again.
      if (mounted) setState(() => _continuing = false);
    }
  }

  void _applyPickedDateTime(DateTime candidate, {bool moved = false}) {
    final corrected = _clampChosen(candidate, widget.now?.call());
    setState(() {
      _selectedDateTime = corrected;
      _pickupCorrectionMessage = corrected == candidate && !moved
          ? null
          : _beyondHorizon(candidate)
          ? context.l10n.pickupTimeWithinHorizon(widget.horizonDays)
          : context.l10n.pickupTimeUpdated;
    });
    _commitSchedule();
  }

  void _commitSchedule() {
    widget.session?.captureSchedule(
      _pickupAt,
      timezone: widget.timeZone,
    );
  }

  void _setPickupMode(bool pickupMode) {
    _pickupMode = pickupMode;
    // The same time now means the other thing; re-check its pickup.
    _applyPickedDateTime(_selectedDateTime);
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

  Future<void> _chooseDate() async {
    var draftDate = _selectedDateTime;
    final first = _schedule.zoneNow(widget.now?.call());
    final last = _latestPickup();
    if (draftDate.isBefore(first)) {
      draftDate = _schedule.clampPickup(draftDate, widget.now?.call());
    }
    if (draftDate.isAfter(last)) draftDate = last;
    final result = await MoveraSheet.show<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _line,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Text(
                          context.l10n.selectDate,
                          style: _style(16, weight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          L10n.formatDate(draftDate, 'd MMM yyyy'),
                          style: _style(
                            11,
                            weight: FontWeight.w500,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 305,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: _ink,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: _ink,
                          ),
                          datePickerTheme: const DatePickerThemeData(
                            backgroundColor: Colors.white,
                            headerBackgroundColor: Colors.white,
                            headerForegroundColor: _ink,
                            surfaceTintColor: Colors.transparent,
                          ),
                        ),
                        child: CalendarDatePicker(
                          initialDate: draftDate,
                          firstDate: first,
                          lastDate: last,
                          onDateChanged: (date) {
                            setSheetState(() => draftDate = date);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetAction(
                            label: context.l10n.cancel,
                            filled: false,
                            onTap: () => Navigator.pop(sheetContext),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _sheetAction(
                            label: context.l10n.done,
                            filled: true,
                            onTap: () => Navigator.pop(sheetContext, draftDate),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    _applyPickedDateTime(
      DateTime(
        result.year,
        result.month,
        result.day,
        _selectedDateTime.hour,
        _selectedDateTime.minute,
      ),
    );
  }

  Future<void> _chooseTime() async {
    final min = _schedule.timePickerMinFor(
      _selectedDateTime,
      widget.now?.call(),
    );
    var draft = _selectedDateTime;
    if (draft.isBefore(min)) draft = min;
    var draftHour = draft.hour;
    var draftMinute = (draft.minute ~/ 5) * 5;
    final hourController = FixedExtentScrollController(initialItem: draftHour);
    final minuteController = FixedExtentScrollController(
      initialItem: draftMinute ~/ 5,
    );

    final result = await MoveraSheet.show<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            height: 300,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Text(
                      context.l10n.selectTime,
                      style: _style(16, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.time24Hour,
                      style: _style(
                        10.5,
                        weight: FontWeight.w500,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: hourController,
                              itemExtent: 40,
                              useMagnifier: true,
                              magnification: 1.04,
                              selectionOverlay: const SizedBox.shrink(),
                              childCount: 24,
                              onSelectedItemChanged: (value) {
                                draftHour = value;
                              },
                              itemBuilder: (_, index) => Center(
                                child: Text(
                                  index.toString().padLeft(2, '0'),
                                  style: _style(20, weight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                          Text(':', style: _style(20, weight: FontWeight.w700)),
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: minuteController,
                              itemExtent: 40,
                              useMagnifier: true,
                              magnification: 1.04,
                              selectionOverlay: const SizedBox.shrink(),
                              childCount: 12,
                              onSelectedItemChanged: (value) {
                                draftMinute = value * 5;
                              },
                              itemBuilder: (_, index) => Center(
                                child: Text(
                                  (index * 5).toString().padLeft(2, '0'),
                                  style: _style(20, weight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _sheetAction(
                        label: context.l10n.cancel,
                        filled: false,
                        onTap: () => Navigator.pop(sheetContext),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _sheetAction(
                        label: context.l10n.done,
                        filled: true,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          TimeOfDay(hour: draftHour, minute: draftMinute),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    hourController.dispose();
    minuteController.dispose();
    if (result == null || !mounted) return;
    final candidate = DateTime(
      _selectedDateTime.year,
      _selectedDateTime.month,
      _selectedDateTime.day,
      result.hour,
      result.minute,
    );
    // rider-r4-12: a time the device's own zone skips is normalised by
    // DateTime (02:30 becomes 03:30 on an EU phone); the rider is told it
    // moved rather than booked silently. A time the pickup zone skips is
    // moved by the clamp.
    _applyPickedDateTime(
      candidate,
      moved: candidate.hour != result.hour || candidate.minute != result.minute,
    );
  }

  Widget _sheetAction({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: Material(
        color: filled ? _ink : _surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Text(
              label,
              style: _style(
                12,
                weight: FontWeight.w600,
                color: filled ? Colors.white : _ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.tripMinutes;
    final estimatedTime = trip == null
        ? null
        : _pickupMode
        ? _selectedDateTime.add(Duration(minutes: trip))
        : _pickupAt;

    return PointerInterceptor(
      child: Material(
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
                      _header(context),
                      const SizedBox(height: 30),
                      Text(
                        context.l10n.whenPickUp,
                        style: _style(
                          29,
                          weight: FontWeight.w700,
                          height: 1.16,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        context.l10n.chooseDateTime,
                        style: _style(
                          12.5,
                          weight: FontWeight.w400,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _modeSelector(),
                      const SizedBox(height: 18),
                      _selectionCard(),
                      if (estimatedTime != null) ...[
                        const SizedBox(height: 18),
                        _estimateRow(estimatedTime),
                      ],
                      const SizedBox(height: 25),
                      Text(
                        context.l10n.scheduleCancelTermsNote,
                        style: _style(
                          10.5,
                          weight: FontWeight.w400,
                          color: _muted,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 118,
                        child: Image.asset(
                          'assets/images/schedule_timeline_exact_v3.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _continueButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Material(
          color: _surface,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: widget.onBack ?? () => Navigator.maybePop(context),
            customBorder: const CircleBorder(),
            // rider-u167: named, and the 44 px floor.
            child: Semantics(
              button: true,
              label: context.l10n.back,
              child: const SizedBox(
                width: A11y.minTapIOS,
                height: A11y.minTapIOS,
                child: Icon(Icons.arrow_back_rounded, color: _ink, size: 22),
              ),
            ),
          ),
        ),
        const Spacer(),
        Text(context.l10n.navScheduleRide, style: _style(12, weight: FontWeight.w600)),
        const Spacer(),
        const SizedBox(width: A11y.minTapIOS),
      ],
    );
  }

  Widget _modeSelector() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _modeOption(
            label: context.l10n.pickupAtMode,
            selected: _pickupMode,
            onTap: () => _setPickupMode(true),
          ),
          _modeOption(
            label: context.l10n.arriveByMode,
            selected: !_pickupMode,
            // No trip estimate, no pickup to book from an arrival time.
            onTap: widget.tripMinutes == null
                ? null
                : () => _setPickupMode(false),
          ),
        ],
      ),
    );
  }

  Widget _modeOption({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Text(
              label,
              style: _style(
                12,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? _ink : _muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _selectionRow(
            icon: Icons.calendar_today_outlined,
            label: context.l10n.date,
            value: L10n.formatDate(_selectedDateTime, 'EEE, d MMMM'),
            onTap: _chooseDate,
          ),
          const Divider(height: 1, indent: 58, endIndent: 16, color: _line),
          _selectionRow(
            icon: Icons.schedule_rounded,
            label: context.l10n.time,
            value: DateFormat('HH:mm').format(_selectedDateTime),
            onTap: _chooseTime,
          ),
        ],
      ),
    );
  }

  Widget _selectionRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(icon, color: _ink, size: 20),
              const SizedBox(width: 18),
              Text(
                label,
                style: _style(11, weight: FontWeight.w500, color: _muted),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _style(13, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estimateRow(DateTime time) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: _ink, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _pickupMode ? context.l10n.estimatedArrival : context.l10n.estimatedPickup,
              style: _style(11, weight: FontWeight.w500, color: _muted),
            ),
          ),
          Text(
            DateFormat('HH:mm').format(time),
            style: _style(13, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _continueButton() {
    // rider-u227: a time that went stale while the screen was open is not
    // a grey button; Continue moves it to the next slot and says so.
    final enabled = !_continuing;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return PointerInterceptor(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + bottom + (kIsWeb ? 28 : 0),
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pickupCorrectionMessage != null) ...[
              Text(
                _pickupCorrectionMessage!,
                textAlign: TextAlign.center,
                style: _style(
                  11,
                  weight: FontWeight.w500,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              // rider-u228: the button's own semantics: the visible,
              // localized label (or "Continuing…") and a tap action.
              child: ElevatedButton(
                key: const Key('schedule-continue'),
                onPressed: enabled ? _goNext : null,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _ink,
                  disabledBackgroundColor: _ink.withValues(alpha: 0.38),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: Text(
                  _continuing ? context.l10n.continuing : context.l10n.continueLabel,
                  style: _style(
                    14,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
