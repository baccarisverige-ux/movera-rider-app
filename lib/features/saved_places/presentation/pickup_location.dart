import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/saved_places/application/current_address.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/custom_textfield.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RiderSearchPickupLocation extends StatefulWidget {
  const RiderSearchPickupLocation({
    super.key,
    this.places,
    this.allowCreateShortcut = true,
    this.geocode,
    this.currentAddress,
  });

  final SavedPlacesController? places;
  final bool allowCreateShortcut;

  /// Forward geocoder for the free-text field; defaults to the app's (the
  /// same call destination text uses).
  final Future<PlaceResult?> Function(String query)? geocode;

  /// Resolves "Current location" to a real address; defaults to the device
  /// position plus the app's reverse geocoder.
  final CurrentAddressResolver? currentAddress;

  @override
  State<RiderSearchPickupLocation> createState() =>
      _RiderSearchPickupLocationState();
}

class _RiderSearchPickupLocationState extends State<RiderSearchPickupLocation> {
  late final SavedPlacesController _places;
  final TextEditingController _query = TextEditingController();
  bool _searching = false;
  bool _locating = false;
  String? _searchError;

  /// rider-u222: an address was returned; a second lookup never pops too.
  bool _done = false;

  void _finish(String address) {
    if (_done) return;
    _done = true;
    Navigator.maybePop(context, address);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// D-023: the field had no submit handler, so a typed address went
  /// nowhere. Resolve it with the same forward geocode destination text uses
  /// and return the real place it names; never save unresolved text.
  Future<void> _submitQuery() async {
    final text = _query.text.trim();
    // rider-u222: one lookup at a time; CURRENT may be resolving.
    if (text.isEmpty || _searching || _locating || _done) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    PlaceResult? found;
    var lookupFailed = false;
    try {
      final geocode = widget.geocode ?? AppScope.instance.geocoding.forward;
      found = await geocode(text).timeout(const Duration(seconds: 10));
    } catch (_) {
      // rider-u82: the lookup never ran (offline, timeout), which is not
      // an address that does not exist.
      lookupFailed = true;
    }
    if (!mounted) return;
    if (found == null) {
      setState(() {
        _searching = false;
        _searchError = lookupFailed
            ? context.l10n.apiUnreachable
            : context.l10n.spAddressNotFound;
      });
      return;
    }
    setState(() => _searching = false);
    final address = found.address.trim();
    _finish(address.isNotEmpty ? address : text);
  }

  /// FLOW-4: return the address of where the rider is, never the words
  /// "Current location"; say why when it cannot be found.
  Future<void> _useCurrentLocation() async {
    if (_locating || _searching || _done) return;
    setState(() {
      _locating = true;
      _searchError = null;
    });
    String? address;
    String? error;
    try {
      address = await (widget.currentAddress ?? resolveCurrentAddress)();
    } on CurrentAddressException catch (e) {
      error = e.message;
    } catch (_) {
      error = L10n.current.spWhereYouAreNotFound;
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _searchError = error;
    });
    if (address != null) _finish(address);
  }

  @override
  void initState() {
    super.initState();
    _places = widget.places ?? AppScope.instance.savedPlaces;
    _places.hydrate().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _places.shortcuts();
    final homeSubtitle = _shortcutSubtitle(
      shortcuts,
      'home',
      fallback: context.l10n.spNotSavedYet,
    );
    final workSubtitle = _shortcutSubtitle(
      shortcuts,
      'office',
      fallback: context.l10n.spNotSavedYet,
    );

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              50.height,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // rider-u224: a named 44 px target around the 26 px circle.
                  MoveraHitArea(
                    label: context.l10n.close,
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      height: ResSize.h * 26,
                      width: ResSize.w * 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColor.black,
                      ),
                      child: Icon(Icons.close, color: AppColor.white, size: 19),
                    ),
                  ),
                ],
              ),
              22.height,
              Container(
                padding: EdgeInsets.symmetric(vertical: ResSize.h * 8),
                decoration: BoxDecoration(
                  color: const Color(0xffF3F6FB),
                  border: Border.all(color: AppColor.border, width: 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Stack(
                  children: [
                    customTextfield(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onFieldSubmitted: (_) => unawaited(_submitQuery()),
                      borderColor: Colors.transparent,
                      borderWidth: 0,
                      borderRadius: 0,
                      contentHorizPadding: 10,
                      hint: context.l10n.spPickupLocation,
                      contentVertPadding: 0,
                      fontSize: 16,
                      textColor: AppColor.black,
                      fillColor: Colors.transparent,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            key: const ValueKey('saved-place-search'),
                            tooltip: context.l10n.spSearchAddress,
                            onPressed: _searching || _locating
                                ? null
                                : () => unawaited(_submitQuery()),
                            icon: _searching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search_rounded, size: 20),
                          ),
                          TextButton(
                            // Returns the address of the device position.
                            onPressed: _locating || _searching
                                ? null
                                : () => unawaited(_useCurrentLocation()),
                            child: SizedBox(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Image.asset(
                                    AppAssets.gps,
                                    height: ResSize.h * 18,
                                    color: AppColor.black,
                                  ),
                                  4.width,
                                  TextWidget(
                                    text: context.l10n.pickupCurrentUpper,
                                    fontSize: 8,
                                    fontWeight: fwBold,
                                    color: AppColor.black,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              2.height,
              Row(
                children: [
                  Expanded(
                    child: _buildSavedPlace(
                      icon: AppAssets.home,
                      title: context.l10n.placeHome,
                      subtitle: homeSubtitle,
                      isLeftRounded: true,
                      onTap: _shortcutTap(homeSubtitle),
                    ),
                  ),
                  2.width,
                  Expanded(
                    child: _buildSavedPlace(
                      icon: AppAssets.office,
                      title: context.l10n.placeWork,
                      subtitle: workSubtitle,
                      onTap: _shortcutTap(workSubtitle),
                    ),
                  ),
                  // rider-r4-46: Favorite only adds a place; a picker that
                  // cannot (Add place's own) does not show a dead chip.
                  if (widget.allowCreateShortcut) ...[
                    2.width,
                    InkWell(
                      onTap: () =>
                          _onShortcutTap(subtitle: context.l10n.spNotSavedYet),
                      child: _buildFavorite(),
                    ),
                  ],
                ],
              ),
              10.height,
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResSize.w * 10,
                  vertical: ResSize.h * 14,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColor.liteBlue,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextWidget(
                      text: context.l10n.spYourLastTrip,
                      color: AppColor.black,
                      fontSize: 16,
                      fontWeight: fwSemiBold,
                    ),
                    10.height,
                    _buildEmptyState(
                      icon: Icons.history_rounded,
                      title: context.l10n.spNoRecentTrips,
                      subtitle: context.l10n.spNoRecentTripsBody,
                    ),
                  ],
                ),
              ),
              24.height,
              TextWidget(
                text: context.l10n.spSearchResults,
                color: AppColor.black,
                fontSize: 16,
                fontWeight: fwSemiBold,
              ),
              10.height,
              if (_searchError != null) ...[
                Semantics(
                  liveRegion: true,
                  child: TextWidget(
                    key: const ValueKey('saved-place-search-error'),
                    text: _searchError!,
                    color: const Color(0xFF9A3412),
                    fontSize: 12.5,
                  ),
                ),
                10.height,
              ],
              _buildEmptyState(
                icon: Icons.search_off_rounded,
                title: context.l10n.spNoSearchResults,
                subtitle: context.l10n.spNoSuggestionsBody,
                backgroundColor: const Color(0xffF5F4F1),
              ),
              20.height,
            ],
          ),
        ),
      ),
    );
  }

  bool _isSaved(String subtitle) =>
      subtitle.trim().isNotEmpty && subtitle != context.l10n.spNotSavedYet;

  /// rider-r4-46: an unsaved Home/Work chip has nothing to do when this
  /// picker cannot create shortcuts, so it is not tappable.
  VoidCallback? _shortcutTap(String subtitle) =>
      _isSaved(subtitle) || widget.allowCreateShortcut
      ? () => _onShortcutTap(subtitle: subtitle)
      : null;

  void _onShortcutTap({required String subtitle}) {
    if (_isSaved(subtitle)) {
      Navigator.maybePop(context, subtitle);
      return;
    }
    if (!widget.allowCreateShortcut) return;
    Navigator.push(
      context,
      RightToLeftTransition(AddPlace(controller: _places)),
    ).then((_) async {
      await _places.hydrate();
      if (mounted) setState(() {});
    });
  }

  double _chipHeight() {
    final scaled = ResSize.h * 57;
    return scaled < 56 ? 56 : scaled;
  }

  Widget _buildSavedPlace({
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isLeftRounded = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: isLeftRounded
            ? const BorderRadius.only(bottomLeft: Radius.circular(10))
            : BorderRadius.zero,
        child: Container(
          constraints: BoxConstraints(minHeight: _chipHeight()),
          decoration: BoxDecoration(
            borderRadius: isLeftRounded
                ? const BorderRadius.only(bottomLeft: Radius.circular(10))
                : null,
            color: AppColor.liteBlue,
            border: Border.all(color: AppColor.border, width: 0.5),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: ResSize.w * 10),
            child: Row(
              children: [
                Image.asset(icon, height: ResSize.h * 20),
                10.width,
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextWidget(
                        text: title,
                        fontSize: 12,
                        fontWeight: fwSemiBold,
                        color: const Color(0xff5E5E5E),
                      ),
                      2.height,
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: fwNormal,
                          color: const Color(0xff5E5E5E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavorite() {
    return Container(
      constraints: BoxConstraints(minHeight: _chipHeight()),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
        color: AppColor.liteBlue,
        border: Border.all(color: AppColor.border, width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ResSize.w * 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(AppAssets.star, height: ResSize.h * 18),
            4.height,
            TextWidget(
              text: context.l10n.spFavorite,
              fontSize: 12,
              fontWeight: fwSemiBold,
              color: const Color(0xff5E5E5E),
            ),
          ],
        ),
      ),
    );
  }

  String _shortcutSubtitle(
    List<PlaceShortcut> shortcuts,
    String kind, {
    required String fallback,
  }) {
    for (final shortcut in shortcuts) {
      if (shortcut.kind == kind) {
        final subtitle = shortcut.subtitle.trim();
        if (subtitle.isNotEmpty) return subtitle;
      }
    }
    return fallback;
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    IconData icon = Icons.info_outline_rounded,
    Color? backgroundColor,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResSize.w * 10,
        vertical: ResSize.h * 12,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColor.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColor.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: ResSize.h * 18, color: AppColor.subtitle),
          8.width,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextWidget(
                  text: title,
                  color: AppColor.black,
                  fontSize: 12,
                  fontWeight: fwSemiBold,
                ),
                2.height,
                TextWidget(
                  text: subtitle,
                  color: const Color(0xff5E5E5E),
                  fontSize: 10,
                  fontWeight: fwNormal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
