import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/destination_search/application/compact_address.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/application/destination_search_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_route_location_badge.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';

/// What the rider picked on [RoutePickerPage].
class RoutePickerSelection {
  const RoutePickerSelection({
    required this.pickup,
    required this.destination,
    required this.stops,
    this.pickupPoint,
    this.destinationPoint,
  });

  final String pickup;
  final GeoPoint? pickupPoint;
  final String destination;
  final GeoPoint? destinationPoint;
  final List<String> stops;
}

/// A point the rider placed on the map from inside the picker.
class RoutePickerMapPick {
  const RoutePickerMapPick({required this.address, required this.point});
  final String address;
  final GeoPoint point;
}

/// Full-screen "Where to?": pickup, optional stops and destination, with
/// address suggestions while typing. Tapping a real address moves on — there
/// is no Next button.
class RoutePickerPage extends StatefulWidget {
  const RoutePickerPage({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.stops,
    required this.stopsSupported,
    required this.initialField,
    required this.capture,
    required this.here,
    required this.homeAddress,
    required this.workAddress,
    this.savedPlaces = const [],
    this.pageTitle = RoutePickerPage.title,
    this.pickupLocked = false,
    this.openWithNewStop = false,
    this.finishLabel,
    required this.recent,
    required this.onSetFavourite,
    required this.onPickOnMap,
    required this.onFinish,
  });

  /// The rider's exact pickup address, or null while it is still unknown.
  final String? pickupAddress;
  final String destinationAddress;
  final List<String> stops;
  final bool stopsSupported;
  final String initialField;
  final EarlyInputCapture capture;
  final GeoPoint? here;
  final String? homeAddress;
  final String? workAddress;

  /// The rider's custom places (gym, school…), listed after Home and Work
  /// with the same icons as the Home page.
  final List<SavedPlaceData> savedPlaces;
  final List<String> recent;

  /// Header text; "Change route" while a ride is live.
  final String pageTitle;

  /// The driver is already at the pickup: it is shown but cannot change.
  final bool pickupLocked;

  /// Opens with an empty new stop focused (the "Add stop" entry point).
  final bool openWithNewStop;

  /// Shows a bottom button that runs [onFinish] with the current route, for
  /// screens where the destination is already filled in.
  final String? finishLabel;

  /// Opens the "Set your address" popup; returns the saved address.
  final Future<String?> Function(String target) onSetFavourite;

  /// Opens "Choose on map" for the pickup or the destination.
  final Future<RoutePickerMapPick?> Function({
    required bool pickup,
    required String address,
  })
  onPickOnMap;

  /// Runs the next booking step; returns the draft to pop with, or null to
  /// stay on this screen.
  final Future<Map<String, dynamic>?> Function(RoutePickerSelection selection)
  onFinish;

  static const String title = 'Plan your ride';

  @override
  State<RoutePickerPage> createState() => _RoutePickerPageState();
}

class _RoutePickerPageState extends State<RoutePickerPage> {
  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFEEF1F2);
  static const Color _box = Color(0xFFF3F5F6);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _pickupGreen = Color(0xFF079A60);
  static const Color _destinationBlue = Color(0xFF1769E8);
  static const int _maxStops = 3;

  /// Fields show the short "street, city" form; the full geocoder address
  /// is what the booking receives when the rider leaves the text as is.
  final Map<String, String> _fullAddress = {};

  String _show(String address) {
    final short = compactAddress(address);
    if (short.isNotEmpty && short != address.trim()) {
      _fullAddress[short] = address.trim();
    }
    return short;
  }

  String _expand(String text) {
    final clean = text.trim();
    return _fullAddress[clean] ?? clean;
  }

  late final TextEditingController _pickup = TextEditingController(
    text: _show(widget.pickupAddress ?? ''),
  );
  late final TextEditingController _destination = TextEditingController(
    text: widget.destinationAddress,
  );
  late final List<TextEditingController> _stops = [
    if (widget.stopsSupported)
      for (final stop in widget.stops) TextEditingController(text: stop),
  ];
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  late final List<FocusNode> _stopFocus = [for (final _ in _stops) FocusNode()];

  late String _active = widget.initialField;
  int _activeStop = -1;
  String _query = '';
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  bool _showAll = false;
  bool _finishing = false;
  GeoPoint? _pickupPoint;
  GeoPoint? _destinationPoint;
  late String? _home = widget.homeAddress;
  late String? _work = widget.workAddress;

  TextEditingController get _activeController {
    if (_active == 'pickup') return _pickup;
    if (_active == 'stop' && _activeStop >= 0 && _activeStop < _stops.length) {
      return _stops[_activeStop];
    }
    return _destination;
  }

  @override
  void initState() {
    super.initState();
    _pickupPoint = widget.here;
    if (widget.openWithNewStop &&
        widget.stopsSupported &&
        _stops.length < _maxStops) {
      _stops.add(TextEditingController());
      _stopFocus.add(FocusNode());
      _active = 'stop';
      _activeStop = _stops.length - 1;
    } else if (_active == 'pickup' && widget.pickupLocked) {
      _active = 'destination';
    }
    final focus = _active == 'pickup'
        ? _pickupFocus
        : _active == 'stop'
        ? _stopFocus[_activeStop]
        : _destinationFocus;
    widget.capture.attach(_activeController, focus);
    widget.capture.onChanged = _onTyped;
    // Opened on a field that already has an address (changing the route of a
    // live ride): typing replaces it instead of adding to its end.
    final prefilled = _activeController;
    if (prefilled.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeController != prefilled) return;
        prefilled.selection = TextSelection(
          baseOffset: 0,
          extentOffset: prefilled.text.length,
        );
      });
    }
    for (final node in [_pickupFocus, _destinationFocus]) {
      node.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.capture.onChanged = null;
    _pickup.dispose();
    _destination.dispose();
    for (final c in _stops) {
      c.dispose();
    }
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    for (final f in _stopFocus) {
      f.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (_pickupFocus.hasFocus && _active != 'pickup') {
      _activate('pickup');
    } else if (_destinationFocus.hasFocus && _active != 'destination') {
      _activate('destination');
    }
  }

  void _activate(String field, {int stop = -1}) {
    if (field == 'pickup' && widget.pickupLocked) return;
    setState(() {
      _active = field;
      _activeStop = stop;
      _query = '';
      _results = const [];
      _showAll = false;
    });
  }

  void _onTyped(String value) {
    if (_active == 'pickup') _pickupPoint = null;
    if (_active == 'destination') _destinationPoint = null;
    setState(() {
      _query = value;
      _showAll = false;
      _searching = value.trim().isNotEmpty;
      if (value.trim().isEmpty) _results = const [];
    });
    if (value.trim().isEmpty) return;
    unawaited(
      AppScope.instance.destinationSearch.suggest(
        value,
        near: widget.here,
        onReady: (query, results) {
          if (!mounted || query != _activeController.text) return;
          setState(() {
            _results = results;
            _searching = false;
          });
        },
      ),
    );
  }

  void _clear() {
    _activeController.clear();
    _onTyped('');
  }

  void _swap() {
    if (widget.pickupLocked) return;
    final pickupText = _pickup.text;
    final pickupPoint = _pickupPoint;
    setState(() {
      _pickup.text = _destination.text;
      _pickupPoint = _destinationPoint;
      _destination.text = pickupText;
      _destinationPoint = pickupPoint;
    });
  }

  void _addStop() {
    if (_stops.length >= _maxStops) return;
    final controller = TextEditingController();
    final focus = FocusNode();
    setState(() {
      _stops.add(controller);
      _stopFocus.add(focus);
    });
    _activate('stop', stop: _stops.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _removeStop(int index) {
    final controller = _stops.removeAt(index);
    final focus = _stopFocus.removeAt(index);
    controller.dispose();
    focus.dispose();
    _activate('destination');
    _destinationFocus.requestFocus();
  }

  Future<void> _choose(String address, {GeoPoint? point}) async {
    if (_finishing) return;
    if (_active == 'pickup') {
      setState(() {
        _pickup.text = _show(address);
        _pickupPoint = point;
      });
      if (_destination.text.trim().isEmpty) {
        _activate('destination');
        _destinationFocus.requestFocus();
        return;
      }
    } else if (_active == 'stop') {
      setState(() => _activeController.text = _show(address));
      _activate('destination');
      _destinationFocus.requestFocus();
      return;
    } else {
      setState(() {
        _destination.text = _show(address);
        _destinationPoint = point;
      });
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing || _destination.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _finishing = true);
    Map<String, dynamic>? draft;
    try {
      draft = await widget.onFinish(
        RoutePickerSelection(
          pickup: _expand(_pickup.text),
          pickupPoint: _pickupPoint,
          destination: _expand(_destination.text),
          destinationPoint: _destinationPoint,
          stops: [
            for (final c in _stops)
              if (c.text.trim().isNotEmpty) _expand(c.text),
          ],
        ),
      );
    } catch (_) {
      // UI-02: a failed lookup (offline, timeout) used to leave the picker
      // busy for good, ignoring every later tap. Say so and stay usable.
      if (mounted) _showFinishFailed();
    } finally {
      if (mounted && draft == null) setState(() => _finishing = false);
    }
    if (!mounted || draft == null) return;
    Navigator.of(context).pop(draft);
  }

  void _showFinishFailed() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('route-picker-finish-failed'),
          content: const Text(
            "Couldn't reach Movera. Check your connection and try again.",
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Try again', onPressed: _finish),
        ),
      );
  }

  Future<void> _pickOnMap() async {
    final pickup = _active == 'pickup';
    final result = await widget.onPickOnMap(
      pickup: pickup,
      address: _activeController.text.trim(),
    );
    if (result == null || !mounted) return;
    await _choose(result.address, point: result.point);
  }

  Future<void> _setFavourite(String target) async {
    final saved = await widget.onSetFavourite(target);
    if (!mounted || saved == null || saved.trim().isEmpty) return;
    setState(() {
      if (target == 'home') _home = saved;
      if (target == 'work') _work = saved;
    });
  }

  TextStyle _t(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
  }) => GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

  // ---------------------------------------------------------------- fields

  Widget _field({
    required String field,
    required TextEditingController controller,
    required FocusNode focus,
    required String hint,
    required Widget leading,
    int stop = -1,
  }) {
    final active = _active == field && (field != 'stop' || _activeStop == stop);
    final locked = field == 'pickup' && widget.pickupLocked;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 56,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? _accent : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: active,
              readOnly: locked,
              enabled: !locked,
              onTap: () {
                if (!active) _activate(field, stop: stop);
              },
              onChanged: active ? _onTyped : null,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_results.isNotEmpty) {
                  final first = _results.first;
                  _choose(first.address, point: first.point);
                }
              },
              style: _t(16.5, color: locked ? _muted : _ink),
              cursorColor: _accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: _t(
                  16.5,
                  weight: FontWeight.w400,
                  color: const Color(0xFF9AA2A8),
                ),
                border: InputBorder.none,
                // UI-4: not dense, so the field is at least 48 px tall (it
                // was 33); same padding, and the text stays centred.
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              textAlignVertical: TextAlignVertical.center,
            ),
          ),
          if (active && controller.text.isNotEmpty)
            // UI-4: a 44 x 44 target (was 34 x 22); the circle stays put.
            MoveraHitArea(
              label: 'Clear',
              onTap: _clear,
              alignment: Alignment.centerRight,
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFC9CED2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          if (locked)
            Tooltip(
              message: 'Your driver is already on the way to this pickup',
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.lock_outline_rounded,
                  key: const ValueKey('route-picker-pickup-locked'),
                  size: 18,
                  color: _muted,
                ),
              ),
            )
          else if (stop >= 0)
            IconButton(
              onPressed: () => _removeStop(stop),
              icon: const Icon(Icons.close_rounded),
              color: _muted,
              iconSize: 18,
              tooltip: 'Remove stop',
            )
          else if (active)
            // UI-4: a 44 x 44 target (was 42 x 38); the badge stays put.
            MoveraHitArea(
              label: field == 'pickup'
                  ? 'Set pickup on map'
                  : 'Choose destination on map',
              onTap: _pickOnMap,
              alignment: Alignment.centerRight,
              child: PremiumRouteLocationBadge(
                color: field == 'pickup' ? _pickupGreen : _destinationBlue,
                size: 38,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fields() {
    final rows = <Widget>[
      _field(
        field: 'pickup',
        controller: _pickup,
        focus: _pickupFocus,
        // GPS without a street name still works as the pickup point.
        hint: widget.pickupAddress != null
            ? 'Pickup'
            : widget.here != null
            ? 'Your current location'
            : 'Finding your address…',
        leading: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFDCEFE6),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: _pickupGreen,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
      for (var i = 0; i < _stops.length; i++)
        _field(
          field: 'stop',
          controller: _stops[i],
          focus: _stopFocus[i],
          stop: i,
          hint: 'Stop ${i + 1}',
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _ink, width: 2),
            ),
          ),
        ),
      _field(
        field: 'destination',
        controller: _destination,
        focus: _destinationFocus,
        hint: 'Where to?',
        leading: const Icon(Icons.search_rounded, color: _ink, size: 24),
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _box,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: rows),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          children: [
            SizedBox(
              height: 56,
              child: IconButton(
                tooltip: 'Add stop',
                onPressed: widget.stopsSupported && _stops.length < _maxStops
                    ? _addStop
                    : null,
                icon: const Icon(Icons.add_rounded, size: 26),
                color: _ink,
              ),
            ),
            SizedBox(
              height: 56,
              child: IconButton(
                tooltip: 'Swap pickup and destination',
                onPressed: widget.pickupLocked ? null : _swap,
                icon: const Icon(Icons.swap_vert_rounded, size: 26),
                color: _ink,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ list

  Widget _highlighted(String text, {FontWeight base = FontWeight.w500}) {
    final range = matchRange(text, _query);
    if (range == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _t(16, weight: base),
      );
    }
    final (start, end) = range;
    return Text.rich(
      TextSpan(
        style: _t(16, weight: base),
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: _t(16, weight: FontWeight.w700, color: _accent),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _row({
    IconData? icon,
    Widget? leading,
    required Widget title,
    String subtitle = '',
    String? trailing,
    Color iconColor = _muted,
    VoidCallback? onTap,
    bool last = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: leading ?? Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(14, weight: FontWeight.w400, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Text(
                trailing,
                style: _t(14, weight: FontWeight.w400, color: _muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, String) _split(String address) {
    final i = address.indexOf(',');
    if (i < 0) return (address, '');
    return (address.substring(0, i).trim(), address.substring(i + 1).trim());
  }

  List<Widget> _beforeTyping() {
    final rows = <Widget>[];
    if (_active == 'pickup' && widget.pickupAddress != null) {
      rows.add(
        _row(
          icon: Icons.near_me_outlined,
          iconColor: _accent,
          title: Text(
            'My location',
            style: _t(16, weight: FontWeight.w600, color: _accent),
          ),
          subtitle: compactAddress(widget.pickupAddress),
          onTap: () => _choose(widget.pickupAddress!, point: widget.here),
        ),
      );
    }
    for (final (target, label, value) in [
      ('home', 'Home', _home),
      ('work', 'Work', _work),
    ]) {
      final set = value != null && value.trim().isNotEmpty;
      rows.add(
        _row(
          // Same Solar linear icons as the Home sheet chips.
          leading: AppIconAsset(
            target == 'home' ? AppAssets.solarHome : AppAssets.solarCase,
            size: 24,
            color: _ink,
          ),
          title: Text(
            set ? label : 'Set $label',
            style: _t(
              16,
              weight: set ? FontWeight.w500 : FontWeight.w600,
              color: set ? _ink : _accent,
            ),
          ),
          subtitle: set
              ? compactAddress(value)
              : 'Add your ${label.toLowerCase()} address',
          onTap: set ? () => _choose(value) : () => _setFavourite(target),
        ),
      );
    }
    for (final place in widget.savedPlaces) {
      final address = place.address.trim();
      if (address.isEmpty) continue;
      rows.add(
        _row(
          leading: AppIconAsset(
            placeIconAssetFor(place.type),
            size: 24,
            color: _ink,
          ),
          title: Text(placeLabelFor(place.type), style: _t(16)),
          subtitle: compactAddress(address),
          onTap: () => _choose(address),
        ),
      );
    }
    // A short, clean list: three real places, no repeats of the same spot.
    final recent = <String>[];
    final seenRecent = <String>{};
    for (final address in widget.recent) {
      final short = compactAddress(address);
      if (short.isEmpty || short == pickupLocationFallbackLabel) continue;
      if (!seenRecent.add(short.toLowerCase())) continue;
      recent.add(address);
      if (recent.length == 3) break;
    }
    if (recent.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 2),
          child: Text(
            'Recent',
            style: _t(13, weight: FontWeight.w600, color: _muted),
          ),
        ),
      );
      for (var i = 0; i < recent.length; i++) {
        final (title, subtitle) = _split(compactAddress(recent[i]));
        rows.add(
          _row(
            leading: const AppIconAsset(
              AppAssets.solarClock,
              size: 24,
              color: _muted,
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(16),
            ),
            subtitle: subtitle,
            onTap: () => _choose(recent[i]),
            last: i == recent.length - 1,
          ),
        );
      }
    }
    return rows;
  }

  List<Widget> _whileTyping() {
    final recentMatches = widget.recent
        .where((r) => matchRange(r, _query) != null)
        .take(2)
        .toList();
    final shown = _showAll ? _results : _results.take(4).toList();
    final rows = <Widget>[
      for (final address in recentMatches)
        () {
          final (title, subtitle) = _split(compactAddress(address));
          return _row(
            leading: const AppIconAsset(
              AppAssets.solarClock,
              size: 24,
              color: _muted,
            ),
            title: _highlighted(title),
            subtitle: subtitle,
            onTap: () => _choose(address),
          );
        }(),
      for (final s in shown)
        if (!recentMatches.any((r) => r.startsWith(s.title)))
          _row(
            icon: Icons.location_on_outlined,
            title: _highlighted(s.title),
            subtitle: s.subtitle,
            trailing: s.distanceKm(widget.here) == null
                ? null
                : formatDistanceKm(s.distanceKm(widget.here)!),
            onTap: () => _choose(s.address, point: s.point),
          ),
    ];
    if (_results.length > shown.length) {
      rows.add(
        _row(
          icon: Icons.search_rounded,
          iconColor: _ink,
          title: Text('Show more results', style: _t(16)),
          onTap: () => setState(() => _showAll = true),
          last: true,
        ),
      );
    }
    if (rows.isEmpty && _searching) {
      rows.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: _accent,
              ),
            ),
          ),
        ),
      );
    } else if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Text('No address found', style: _t(16, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Check the spelling or choose the place on the map.',
                textAlign: TextAlign.center,
                style: _t(13.5, weight: FontWeight.w400, color: _muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Try the map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final typing = _query.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Swipe down on the header to close, like a sheet.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 300) {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded, size: 26),
                          color: _ink,
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              widget.pageTitle,
                              style: _t(18, weight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 52),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  child: _fields(),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: typing ? _whileTyping() : _beforeTyping(),
                  ),
                ),
              ],
            ),
            if (widget.finishLabel != null &&
                !typing &&
                _destination.text.trim().isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    key: const ValueKey('route-picker-done'),
                    onPressed: _finishing ? null : _finish,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF11181D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      widget.finishLabel!,
                      style: _t(
                        16,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            if (_finishing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33FFFFFF),
                  child: Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
