import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places_style.dart';
import 'package:movera_rider/shared/design_system/movera_confirm_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SavedPlaces extends StatefulWidget {
  const SavedPlaces({super.key, this.controller});

  final SavedPlacesController? controller;

  @override
  State<SavedPlaces> createState() => _SavedPlacesState();
}

class _SavedPlacesState extends State<SavedPlaces> {
  late final SavedPlacesController _places;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _places = widget.controller ?? AppScope.instance.savedPlaces;
    _reload();
  }

  /// FLOW-15: a failed read used to leave the spinner up forever.
  Future<void> _reload() async {
    String? error;
    try {
      await _places.hydrate();
    } catch (e) {
      AppLog.warning('saved_places.load_failed', extra: {'error': '$e'});
      error = L10n.current.spLoadFailed;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  Future<void> _openEditor({PlaceShortcut? place, String? kind}) async {
    final result = await Navigator.push<PlaceShortcut>(
      context,
      RightToLeftTransition(
        AddPlace(controller: _places, initial: place, kind: kind),
      ),
    );
    if (result != null) await _reload();
  }

  /// FLOW-15: asks first, removes only this place, and says so if it fails.
  Future<void> _delete(PlaceShortcut place) async {
    final confirmed = await confirmMoveraAction(
      context,
      title: context.l10n.spRemoveQ(place.title),
      message: place.subtitle,
      confirmLabel: context.l10n.remove,
    );
    if (!confirmed || !mounted) return;
    try {
      await _places.remove(place);
    } catch (e) {
      AppLog.warning('saved_places.remove_failed', extra: {'error': '$e'});
      if (mounted) {
        MoveraToast.show(context, context.l10n.spRemoveFailed(place.title));
      }
    }
    await _reload();
  }

  /// Home's limit (homeMaxCustomPlaces, home_route_flow.dart
  /// `_openAddPlacePicker`) holds when adding from the Menu too.
  void _addPlace() {
    final custom = _places
        .shortcuts()
        .where((p) => p.kind != 'home' && p.kind != 'office')
        .length;
    if (custom >= HomePlacesController.maxCustom) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.homeMaxCustomPlaces)));
      return;
    }
    _openEditor();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _places.shortcuts();
    PlaceShortcut? slot(String kind) =>
        shortcuts.where((p) => p.kind == kind).firstOrNull;
    final home = slot('home');
    final work = slot('office');
    final others = shortcuts
        .where((p) => p.kind != 'home' && p.kind != 'office')
        .toList();
    // Saved places v4 (owner 2026-11-27): white, FAVORITER (Home, Work),
    // ANDRA PLATSER (the rest), then "Lägg till plats".
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // UI-11: a 44 px named tap area.
              SpStyle.back(context, context.l10n.back, () {
                Navigator.pop(context);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpStyle.side),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    8.height,
                    SpStyle.title(context.l10n.menuSavedPlaces),
                    6.height,
                    Text(
                      context.l10n.spQuickTagline,
                      style: SpStyle.text(size: 14, color: SpStyle.muted),
                    ),
                    if (_loading) ...[
                      24.height,
                      const Center(
                        child: CircularProgressIndicator(color: SpStyle.ink),
                      ),
                    ] else if (_loadError != null) ...[
                      24.height,
                      Text(
                        _loadError!,
                        style: SpStyle.text(size: 14, color: SpStyle.muted),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: SpStyle.ink,
                        ),
                        onPressed: () {
                          setState(() => _loading = true);
                          _reload();
                        },
                        child: Text(context.l10n.tryAgain),
                      ),
                    ] else ...[
                      SpStyle.section(context.l10n.spFavoritesHeader),
                      home == null
                          ? _addRow(context.l10n.spAddHome, 'home')
                          : _savedRow(home),
                      work == null
                          ? _addRow(context.l10n.spAddWork, 'office')
                          : _savedRow(work),
                      if (others.isNotEmpty) ...[
                        SpStyle.section(context.l10n.spOtherPlacesHeader),
                        for (final place in others) _savedRow(place),
                      ],
                      SpStyle.row(
                        key: const ValueKey('saved-places-add'),
                        icon: Icons.add,
                        name: context.l10n.spAddLocation,
                        divider: false,
                        onTap: _addPlace,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _savedRow(PlaceShortcut place) {
    return SpStyle.row(
      icon: placeTypeIcon(place.kind),
      name: place.title,
      address: place.subtitle,
      onTap: () => _openEditor(place: place),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.spEditPlace(place.title),
            onPressed: () => _openEditor(place: place),
            icon: const Icon(Icons.edit_outlined, color: SpStyle.ink, size: 20),
          ),
          IconButton(
            tooltip: context.l10n.spDeletePlace(place.title),
            onPressed: () => _delete(place),
            icon: const Icon(
              Icons.delete_outline,
              color: SpStyle.ink,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _addRow(String title, String kind) {
    return SpStyle.row(
      icon: placeTypeIcon(kind),
      name: title,
      onTap: () => _openEditor(kind: kind),
      trailing: const Icon(Icons.chevron_right, color: SpStyle.muted, size: 20),
    );
  }
}
