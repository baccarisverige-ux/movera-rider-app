import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/features/saved_places/application/quick_save.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One category the rider can fix for a place (id + shown name).
typedef PlaceCategoryChoice = ({String id, String name});

/// Saved-places design S3 (owner 2026-11-18, steps 3b, 4, 4b): on the
/// categories screen opened from a recent address that is not saved, a
/// small sheet slides up about [delay] after the screen opens: "Spara
/// adressen?" with the address and the type chips. A type tap saves the
/// place ("Sparad som {type}" + "Ångra"), then asks for a fixed category
/// (the available categories + "Nej tack"; only on a server that knows
/// the field). The ✕, a swipe down or a tap anywhere outside the sheet
/// closes it (= ignore). It never blocks booking: nothing is shown under
/// it until it appears, and it goes away for good once closed.
class PlaceSaveSheet extends StatefulWidget {
  const PlaceSaveSheet({
    super.key,
    required this.address,
    required this.categories,
    this.quickSave,
    this.delay = const Duration(seconds: 2),
  });

  final String address;

  /// The categories available here now (read when the question shows).
  final List<PlaceCategoryChoice> Function() categories;
  final PlaceQuickSave? quickSave;
  final Duration delay;

  @override
  State<PlaceSaveSheet> createState() => _PlaceSaveSheetState();
}

class _PlaceSaveSheetState extends State<PlaceSaveSheet>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF111614);
  static const _muted = Color(0xFF5B615E);
  static const _green = Color(0xFF117C4B);

  late final PlaceQuickSave _save = widget.quickSave ?? PlaceQuickSave();
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Timer? _timer;
  bool _closed = false;
  String? _savedType;
  Object? _before;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted && !_closed) _slide.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closed) return;
    _timer?.cancel();
    await _slide.reverse();
    if (mounted) setState(() => _closed = true);
  }

  Future<void> _pickType(String type) async {
    final before = await _save.save(widget.address, type);
    if (!mounted) return;
    setState(() {
      _savedType = type;
      _before = before;
    });
    if (!_save.categorySupported || widget.categories().isEmpty) {
      // An older server: no category question; the confirmation stays a
      // moment with its undo, then the sheet goes.
      Timer(const Duration(seconds: 4), () {
        if (mounted) unawaited(_close());
      });
    }
  }

  Future<void> _undo() async {
    final before = _before;
    if (before != null) await _save.undo(before);
    if (mounted) unawaited(_close());
  }

  Future<void> _fix(String categoryId) async {
    final type = _savedType;
    if (type != null) {
      await _save.fixCategory(widget.address, type, categoryId);
    }
    if (mounted) unawaited(_close());
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, child) {
        if (_slide.isDismissed) return const SizedBox.shrink();
        // Over the web map the taps must reach Flutter, not the map.
        return PointerInterceptor(
          child: Stack(
            children: [
              // Step 4b: a tap anywhere outside the sheet closes it.
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('place-save-outside'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionalTranslation(
                  translation: Offset(
                    0,
                    1 - Curves.easeOutCubic.transform(_slide.value),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: GestureDetector(
        key: const ValueKey('place-save-sheet'),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 100) unawaited(_close());
        },
        onTap: () {}, // a tap inside is not "outside"
        child: Material(
          color: Colors.white,
          elevation: 20,
          shadowColor: const Color(0x33162C36),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x33111614),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (_savedType == null)
                    ..._ask(context)
                  else
                    ..._saved(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) => IconButton(
    key: const ValueKey('place-save-close'),
    tooltip: context.l10n.close,
    onPressed: _close,
    icon: const Icon(Icons.close_rounded, size: 20, color: _muted),
  );

  List<Widget> _ask(BuildContext context) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, right: 8),
          child: Icon(Icons.bookmark_add_outlined, size: 20, color: _ink),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.placesSaveAddress,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
        ),
        _closeButton(context),
      ],
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in PlaceQuickSave.types)
          _chip(
            key: ValueKey('place-save-type-$type'),
            icon: placeTypeIcon(type),
            label: PlaceQuickSave.label(type),
            onTap: () => _pickType(type),
          ),
      ],
    ),
  ];

  List<Widget> _saved(BuildContext context) {
    final ask = _save.categorySupported ? widget.categories() : const [];
    return [
      Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: _green),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            flex: 3,
            child: Text(
              context.l10n.placesSavedAs(PlaceQuickSave.label(_savedType!)),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _green,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              strutStyle: const StrutStyle(fontSize: 14.5),
            ),
          ),
          TextButton(
            key: const ValueKey('place-save-undo'),
            onPressed: _undo,
            child: Text(
              context.l10n.placesUndo,
              style: const TextStyle(
                color: _ink,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const Spacer(flex: 1),
          _closeButton(context),
        ],
      ),
      if (ask.isNotEmpty) ...[
        Text(
          context.l10n.placesAskFixCategory,
          style: const TextStyle(fontSize: 13.5, color: _ink),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in ask)
              _chip(
                key: ValueKey('place-save-category-${c.id}'),
                label: c.name,
                onTap: () => _fix(c.id),
              ),
            TextButton(
              key: const ValueKey('place-save-no-thanks'),
              onPressed: _close,
              child: Text(
                context.l10n.placesNoThanks,
                style: const TextStyle(color: _muted),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _chip({
    required Key key,
    IconData? icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: _ink.withValues(alpha: 0.14)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: _ink),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon of a place type, the same as Home's saved places row (Hem a
/// house, Jobb a work bag, custom types their own).
IconData placeTypeIcon(String type) => switch (type) {
  'home' => Icons.home_outlined,
  'work' || 'office' => Icons.work_outline,
  'gym' => Icons.fitness_center_rounded,
  'mall' => Icons.local_mall_outlined,
  'school' => Icons.school_outlined,
  'airport' => Icons.flight_takeoff_rounded,
  'family' => Icons.family_restroom_rounded,
  'restaurant' => Icons.restaurant_rounded,
  _ => Icons.place_outlined,
};
