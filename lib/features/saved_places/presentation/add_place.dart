import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/saved_places/application/current_address.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places_style.dart';
import 'package:movera_rider/shared/design_system/movera_confirm_sheet.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/keyboard_anchor.dart';

class AddPlace extends StatefulWidget {
  const AddPlace({
    super.key,
    this.controller,
    this.initial,
    this.kind,
    this.currentAddress,
  });

  final SavedPlacesController? controller;
  final PlaceShortcut? initial;
  final String? kind;

  /// Passed to the location picker's "Current location" button.
  final CurrentAddressResolver? currentAddress;

  @override
  State<AddPlace> createState() => _AddPlaceState();
}

class _AddPlaceState extends State<AddPlace> {
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final SavedPlacesController _places;
  String? _error;
  bool _saving = false;

  /// The place type chosen with the chips; null = from the name, as before.
  String? _type;

  @override
  void initState() {
    super.initState();
    _places = widget.controller ?? AppScope.instance.savedPlaces;
    _nameController = TextEditingController(
      text:
          widget.initial?.title ??
          switch (_slot) {
            'home' => L10n.current.placeHome,
            'office' => L10n.current.placeWork,
            _ => '',
          },
    );
    final initialKind = widget.initial?.kind.trim() ?? widget.kind?.trim();
    if (placeTypes.contains(initialKind)) _type = initialKind;
    _locationController = TextEditingController(
      text: widget.initial?.subtitle ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final selected = await Navigator.push<String>(
      context,
      BottomToTopTransition(
        RiderSearchPickupLocation(
          allowCreateShortcut: false,
          places: _places,
          currentAddress: widget.currentAddress,
        ),
      ),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    setState(() {
      _locationController.text = selected.trim();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    if (name.isEmpty || location.isEmpty) {
      setState(() => _error = context.l10n.spNameAndLocation);
      return;
    }

    // Saved places v4: a chosen type is the kind (stored as `type`, sent as
    // kind other + that key, as Home's picker saves it).
    final kind = _slot ?? _type ?? _kindFor(name);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // FLOW-5: a new place named "Home" or "Work" goes into that slot, so
      // ask before it replaces the address already saved there.
      if (_isNewPlace && (kind == 'home' || kind == 'office')) {
        await _places.hydrate();
        final label = kind == 'home'
            ? L10n.current.placeHome
            : L10n.current.placeWork;
        final taken = _places.shortcuts().any((p) => p.kind == kind);
        if (taken) {
          if (!mounted) return;
          final replace = await confirmMoveraAction(
            context,
            title: context.l10n.spReplaceQ(label),
            message: context.l10n.spReplaceBody(label, location),
            confirmLabel: context.l10n.spReplaceConfirm(label),
          );
          if (!mounted) return;
          if (!replace) {
            setState(() => _saving = false);
            return;
          }
        }
      }
      // Home's limit (homeMaxCustomPlaces) holds here too: a new custom
      // place is refused once the rider has the most Home can show.
      if (widget.initial?.id == null && kind != 'home' && kind != 'office') {
        await _places.hydrate();
        final custom = _places
            .shortcuts()
            .where((p) => p.kind != 'home' && p.kind != 'office')
            .length;
        if (custom >= HomePlacesController.maxCustom) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _error = context.l10n.homeMaxCustomPlaces;
          });
          return;
        }
      }
      final saved = await _places.save(
        PlaceShortcut(
          title: name,
          subtitle: location,
          kind: kind,
          id: widget.initial?.id,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.spSaveFailed;
      });
    }
  }

  /// rider-r4-47: the Home or Work slot this screen edits, if any. Those
  /// keep their name (the controller stores only the address there), so
  /// the name field is not editable rather than silently ignored.
  String? get _slot {
    final requested = widget.kind?.trim();
    final kind = requested?.isNotEmpty == true
        ? requested!
        : widget.initial?.kind.trim();
    return kind == 'home' || kind == 'office' ? kind : null;
  }

  bool get _isNewPlace =>
      widget.initial == null && (widget.kind?.trim().isEmpty ?? true);

  String _kindFor(String name) {
    final existing = widget.initial?.kind.trim();
    final requested = widget.kind?.trim();
    final raw = requested?.isNotEmpty == true
        ? requested!
        : existing?.isNotEmpty == true
        ? existing!
        : name;
    final lower = raw.toLowerCase();
    if (lower == 'work') return 'office';
    // A new place named Home or Work in the app language takes that slot.
    if (lower == L10n.current.placeHome.toLowerCase()) return 'home';
    if (lower == L10n.current.placeWork.toLowerCase()) return 'office';
    final slug = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'other' : slug;
  }

  /// Saved places v4 (owner 2026-11-27): Home's 7 place types
  /// (home_route_flow.dart `_openAddPlacePicker`), in the same order.
  static const placeTypes = <String>[
    'gym',
    'mall',
    'school',
    'airport',
    'family',
    'restaurant',
    'other',
  ];

  void _pickType(String type) {
    final name = _nameController.text.trim();
    final before = _type;
    setState(() {
      _type = type;
      _error = null;
      // The type's name fills an empty name, or replaces the last type's.
      if (name.isEmpty || (before != null && name == placeLabelFor(before))) {
        _nameController.text = placeLabelFor(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    return Scaffold(
      backgroundColor: Colors.white,
      // rider-u221: a small phone with the keyboard up scrolls the form
      // (the error line included) instead of overflowing it; the Save
      // button still sits at the bottom when there is room.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // UI-11: a 44 px named tap area.
                    SpStyle.back(
                      context,
                      context.l10n.back,
                      () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpStyle.side,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            8.height,
                            SpStyle.title(
                              widget.initial == null
                                  ? (slot == null
                                        ? context.l10n.placeNew
                                        : _nameController.text)
                                  : context.l10n.spEditSavedPlace,
                            ),
                            if (slot == null) ...[
                              20.height,
                              SpStyle.label(context.l10n.homeWhatPlaceToSave),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final type in placeTypes) _chip(type),
                                ],
                              ),
                            ],
                            20.height,
                            SpStyle.label(context.l10n.spName),
                            TextField(
                              controller: _nameController,
                              enabled: slot == null,
                              style: SpStyle.text(),
                              cursorColor: SpStyle.ink,
                              decoration: SpStyle.underline(),
                            ),
                            20.height,
                            SpStyle.label(context.l10n.spAddLocation),
                            InkWell(
                              key: const ValueKey('add-place-address'),
                              onTap: _pickLocation,
                              child: IgnorePointer(
                                child: TextField(
                                  controller: _locationController,
                                  style: SpStyle.text(),
                                  decoration: SpStyle.underline(
                                    hint: context.l10n.spSearchAddress,
                                    prefix: const Icon(
                                      Icons.search,
                                      color: SpStyle.muted,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              12.height,
                              Text(
                                _error!,
                                style: SpStyle.text(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                            const Spacer(),
                            16.height,
                            KeyboardAnchor(
                              child: SpStyle.pill(
                                key: const ValueKey('add-place-save'),
                                label: _saving
                                    ? context.l10n.saving
                                    : context.l10n.spSavePlace,
                                onPressed: _saving ? null : _save,
                              ),
                            ),
                            16.height,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String type) {
    final on = _type == type;
    final fg = on ? Colors.white : SpStyle.ink;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? SpStyle.ink : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: on ? SpStyle.ink : SpStyle.chipBorder),
        ),
        child: InkWell(
          key: ValueKey('place-type-$type'),
          customBorder: const StadiumBorder(),
          onTap: () => _pickType(type),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(placeTypeIcon(type), size: 20, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    placeLabelFor(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpStyle.text(size: 14, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
