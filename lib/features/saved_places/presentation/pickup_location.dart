import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/features/destination_search/presentation/address_suggestion_list.dart';
import 'package:movera_rider/features/saved_places/application/current_address.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places_style.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
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
  final AddressSuggester _suggester = AddressSuggester();
  bool _searching = false;
  bool _locating = false;
  String? _searchError;

  /// rider-u222: an address was returned; a second lookup never pops too.
  bool _done = false;

  void _finish(String address) => _leave(address);

  /// rider-r5-35: every way out (an address, a saved chip, Close) leaves
  /// once, and only while this picker is the top route. A lookup answering
  /// after Close otherwise popped the screen under it (Add place).
  void _leave([String? address]) {
    if (_done) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _done = true;
    Navigator.of(context).pop(address);
  }

  @override
  void dispose() {
    _query.dispose();
    _suggester.dispose();
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
    final typed = _query.text.trim().isNotEmpty;
    // Saved places v4 (owner 2026-11-27): white page, back chevron, an
    // underline search field, then "Use current location" and the real
    // suggestions with the typed part in bold.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // rider-u224: a named 44 px target (Close leaves without an
              // address, as before).
              SpStyle.back(context, context.l10n.close, _leave),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpStyle.side),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    8.height,
                    SpStyle.title(context.l10n.spSearchAddress),
                    20.height,
                    TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => unawaited(_submitQuery()),
                      onChanged: (value) {
                        setState(() => _searchError = null);
                        _suggester.type(value);
                      },
                      style: SpStyle.text(),
                      cursorColor: SpStyle.ink,
                      decoration: SpStyle.underline(
                        hint: context.l10n.spPickupLocation,
                        prefix: const Icon(
                          Icons.search,
                          color: SpStyle.ink,
                          size: 20,
                        ),
                        suffix: IconButton(
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
                                    color: SpStyle.ink,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_forward,
                                  color: SpStyle.ink,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                    8.height,
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
                      8.height,
                    ],
                    // The same suggestions "Where to?" shows while typing;
                    // tapping one returns its address. Enter / search still
                    // geocodes the typed text (D-023) as the fallback.
                    AddressSuggestionList(
                      key: const ValueKey('saved-place-suggestions'),
                      suggester: _suggester,
                      style: AddressSuggestionStyle.plain,
                      currentLocationLabel: _locating
                          ? context.l10n.findingYourAddress
                          : context.l10n.useCurrentLocation,
                      onUseCurrentLocation: _locating || _searching
                          ? () {}
                          : () => unawaited(_useCurrentLocation()),
                      onPick: (s) => _finish(s.address),
                      empty: typed ? _noResults() : _savedShortcuts(shortcuts),
                    ),
                    20.height,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Nothing typed: Home and Work (a saved one returns its address).
  Widget _savedShortcuts(List<PlaceShortcut> shortcuts) {
    Widget slot(String kind, String name, IconData icon) {
      final subtitle = _shortcutSubtitle(
        shortcuts,
        kind,
        fallback: context.l10n.spNotSavedYet,
      );
      return SpStyle.row(
        icon: icon,
        name: name,
        address: subtitle,
        onTap: _shortcutTap(subtitle),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        slot('home', context.l10n.placeHome, placeTypeIcon('home')),
        slot('office', context.l10n.placeWork, placeTypeIcon('office')),
        // rider-r4-46: Favorite only adds a place; a picker that cannot
        // (Add place's own) does not show a dead row.
        if (widget.allowCreateShortcut)
          SpStyle.row(
            icon: Icons.star_outline,
            name: context.l10n.spFavorite,
            divider: false,
            onTap: () => _onShortcutTap(subtitle: context.l10n.spNotSavedYet),
          ),
      ],
    );
  }

  Widget _noResults() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.spNoSearchResults, style: SpStyle.text(size: 14)),
        2.height,
        Text(
          context.l10n.spNoSuggestionsBody,
          style: SpStyle.text(size: 13, color: SpStyle.muted),
        ),
      ],
    ),
  );

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
      _leave(subtitle);
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
}
