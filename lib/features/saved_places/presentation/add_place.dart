import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/saved_places/application/current_address.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/shared/design_system/movera_confirm_sheet.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

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

    final kind = _kindFor(name);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            // UI-11: a 44 px tap area and a name for screen readers; the
            // 30 px circle looks the same.
            child: MoveraHitArea(
              label: context.l10n.back,
              alignment: Alignment.centerLeft,
              onTap: () => Navigator.pop(context),
              child: InkWell(
                excludeFromSemantics: true,
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: ResSize.h * 30,
                  width: ResSize.w * 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColor.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff999999).withValues(alpha: 0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.arrow_back_ios_rounded,
                      color: AppColor.title,
                      size: ResSize.h * 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: TextWidget(
          text: widget.initial == null
              ? context.l10n.spAddNewAddress
              : context.l10n.spEditSavedPlace,
          color: AppColor.title,
          fontSize: 16,
          fontWeight: fwSemiBold,
        ),
        centerTitle: true,
      ),
      // rider-u221: a small phone with the keyboard up scrolls the form
      // (the error line included) instead of overflowing it; the Save
      // button still sits at the bottom when there is room.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    16.height,
                    TextField(
                      controller: _nameController,
                      enabled: _slot == null,
                      style: GoogleFonts.poppins(
                        color: AppColor.title,
                        fontSize: 16,
                        fontWeight: fwNormal,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.spName,
                        labelStyle: GoogleFonts.poppins(
                          color: AppColor.subtitle,
                          fontSize: 14,
                          fontWeight: fwNormal,
                        ),
                      ),
                    ),
                    16.height,
                    InkWell(
                      onTap: _pickLocation,
                      child: IgnorePointer(
                        child: TextField(
                          controller: _locationController,
                          style: GoogleFonts.poppins(
                            color: AppColor.title,
                            fontSize: 16,
                            fontWeight: fwNormal,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.spAddLocation,
                            labelStyle: GoogleFonts.poppins(
                              color: AppColor.subtitle,
                              fontSize: 12,
                              fontWeight: fwNormal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      12.height,
                      Text(
                        _error!,
                        style: GoogleFonts.poppins(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: fwMedium,
                        ),
                      ),
                    ],
                    const Spacer(),
                    SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving ? context.l10n.saving : context.l10n.save,
                          ),
                        ),
                      ),
                    ),
                    16.height,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
