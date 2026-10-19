import 'package:flutter/material.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/shared/design_system/movera_confirm_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';

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
      error = 'Couldn’t load your saved places. Try again.';
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
        AddPlace(
          controller: _places,
          initial: place,
          kind: kind,
        ),
      ),
    );
    if (result != null) await _reload();
  }

  /// FLOW-15: asks first, removes only this place, and says so if it fails.
  Future<void> _delete(PlaceShortcut place) async {
    final confirmed = await confirmMoveraAction(
      context,
      title: 'Remove ${place.title}?',
      message: place.subtitle,
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    try {
      await _places.remove(place);
    } catch (e) {
      AppLog.warning('saved_places.remove_failed', extra: {'error': '$e'});
      if (mounted) {
        MoveraToast.show(context, 'Couldn’t remove ${place.title}. Try again.');
      }
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _places.shortcuts();
    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            55.height,
            // UI-11: a 44 px tap area and a name for screen readers; the
            // 30 px circle looks the same.
            MoveraHitArea(
              label: 'Back',
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
            16.height,
            TextWidget(
              text: 'Saved Places',
              color: AppColor.title,
              fontSize: 20,
              fontWeight: fwMedium,
            ),
            TextWidget(
              text: 'The driver will take you where you’re going',
              color: AppColor.subtitle,
              fontSize: 14,
              fontWeight: fwMedium,
            ),
            24.height,
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_loadError != null) ...[
              Text(_loadError!, style: TextStyle(color: AppColor.subtitle)),
              TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _reload();
                },
                child: const Text('Try again'),
              ),
            ] else ...[
              for (final place in shortcuts) _savedRow(place),
              if (!shortcuts.any((item) => item.kind == 'home'))
                _addRow('Add Home', 'home', Icons.house_rounded),
              if (!shortcuts.any((item) => item.kind == 'office'))
                _addRow('Add Work', 'office', Icons.work_outline_rounded),
              if (!shortcuts.any((item) => item.kind == 'school'))
                _addRow('Add School', 'school', Icons.bookmark_outline_rounded),
              if (!shortcuts.any((item) => item.kind == 'gym'))
                _addRow('Add Gym', 'gym', Icons.fitness_center_rounded),
              _addRow('Add another place', null, Icons.add_location_alt_outlined),
            ],
          ],
        ),
      ),
    );
  }

  Widget _savedRow(PlaceShortcut place) {
    return Column(
      children: [
        10.height,
        Row(
          children: [
            const Icon(Icons.place_outlined),
            10.width,
            Expanded(
              child: InkWell(
                onTap: () => _openEditor(place: place),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.title),
                    Text(
                      place.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColor.subtitle, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit ${place.title}',
              onPressed: () => _openEditor(place: place),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete ${place.title}',
              onPressed: () => _delete(place),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Divider(color: AppColor.border, thickness: 0.5),
      ],
    );
  }

  Widget _addRow(String title, String? kind, IconData icon) {
    return InkWell(
      onTap: () => _openEditor(kind: kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColor.subtitle, size: ResSize.h * 24),
            10.width,
            Expanded(
              child: TextWidget(
                text: title,
                color: AppColor.subtitle,
                fontSize: 14,
                fontWeight: fwMedium,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColor.subtitle,
              size: ResSize.h * 18,
            ),
          ],
        ),
      ),
    );
  }
}
