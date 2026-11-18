import 'package:flutter/material.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/saved_places/application/quick_save.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One saved place as the pop-up lists it.
class PopupPlace {
  const PopupPlace({
    required this.kind,
    required this.title,
    required this.address,
    this.type,
  });

  /// home | work | custom.
  final String kind;
  final String title;
  final String address;

  /// A custom place's type (gym, school, ...).
  final String? type;

  String get iconType => kind == 'custom' ? (type ?? 'other') : kind;
}

/// What the rider chose in the pop-up.
sealed class PlacesPopupChoice {
  const PlacesPopupChoice();
}

class PickSavedPlace extends PlacesPopupChoice {
  const PickSavedPlace(this.place);
  final PopupPlace place;
}

class PickRecent extends PlacesPopupChoice {
  const PickRecent(this.address);
  final String address;
}

class PickAddPlace extends PlacesPopupChoice {
  const PickAddPlace();
}

class PickWhereTo extends PlacesPopupChoice {
  const PickWhereTo();
}

class PickLater extends PlacesPopupChoice {
  const PickLater();
}

/// Saved-places design step 2 (owner 2026-11-18, P2-3 in
/// mock/step2-popup.png): a full-width solid white sheet slides down from
/// under the status bar, with a big title, the capsule (pin chip black,
/// arrow up), "Sparade platser" (Hem, Jobb, the other places), "Lägg till
/// plats", "Senaste adresser" and the "Vart vill du åka?" bar with
/// "Senare" at the bottom. The list scrolls; the map behind is dimmed. A
/// tap on the dim, the capsule, the grab handle or a swipe up closes it.
class PlacesPopup extends StatelessWidget {
  const PlacesPopup({
    super.key,
    required this.places,
    required this.recent,
    this.onMenuTap,
  });

  final List<PopupPlace> places;
  final List<String> recent;
  final VoidCallback? onMenuTap;

  static const _ink = Color(0xFF111614);
  static const _muted = Color(0xFF6B716E);
  static const _blue = PremiumTopActions.pinBlue;

  /// Opens the pop-up over [context]; answers the rider's choice or null.
  static Future<PlacesPopupChoice?> open(
    BuildContext context, {
    required List<PopupPlace> places,
    required List<String> recent,
    VoidCallback? onMenuTap,
  }) {
    return showGeneralDialog<PlacesPopupChoice>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.close,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, __) =>
          PlacesPopup(places: places, recent: recent, onMenuTap: onMenuTap),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final l10n = context.l10n;
    void pick(PlacesPopupChoice c) => Navigator.of(context).pop(c);
    return Align(
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -100) Navigator.of(context).pop();
        },
        child: Material(
          key: const ValueKey('places-popup'),
          color: Colors.white,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.72),
            child: Padding(
              padding: EdgeInsets.only(top: media.padding.top),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.menuSavedPlaces,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 46,
                          child: PremiumTopActions(
                            onMenuTap: () {
                              Navigator.of(context).pop();
                              onMenuTap?.call();
                            },
                            onPlacesTap: () => Navigator.of(context).pop(),
                            placesOpen: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final p in places)
                          _row(
                            key: ValueKey(
                              'places-popup-place-${p.kind}-${p.title}',
                            ),
                            icon: placeTypeIcon(p.iconType),
                            title: p.title,
                            subtitle: p.address,
                            chevron: true,
                            onTap: () => pick(PickSavedPlace(p)),
                          ),
                        ListTile(
                          key: const ValueKey('places-popup-add'),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          minLeadingWidth: 24,
                          leading: const Icon(Icons.add, color: _blue),
                          title: Text(
                            l10n.spAddLocation,
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => pick(const PickAddPlace()),
                        ),
                        if (recent.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                            child: Text(
                              l10n.recentAddresses,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                          ),
                          for (final (i, a) in recent.indexed)
                            _row(
                              key: ValueKey('places-popup-recent-$i'),
                              icon: Icons.history_rounded,
                              title: _head(a),
                              subtitle: _tail(a),
                              chevron: false,
                              onTap: () => pick(PickRecent(a)),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _whereToBar(context, pick),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _ink.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _head(String a) {
    final i = a.indexOf(',');
    return i < 0 ? a : a.substring(0, i).trim();
  }

  static String _tail(String a) {
    final i = a.indexOf(',');
    return i < 0 ? '' : a.substring(i + 1).trim();
  }

  Widget _row({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool chevron,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 9, 16, 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _ink.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: _ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                ],
              ),
            ),
            if (chevron)
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _whereToBar(
    BuildContext context,
    void Function(PlacesPopupChoice) pick,
  ) {
    return Material(
      color: const Color(0xFFF3F4F3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('places-popup-where-to'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => pick(const PickWhereTo()),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.search_rounded, color: _ink, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.whereTo,
                  style: const TextStyle(fontSize: 18, color: _ink),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(color: _ink.withValues(alpha: 0.10)),
                  ),
                  child: InkWell(
                    key: const ValueKey('places-popup-later'),
                    customBorder: const StadiumBorder(),
                    onTap: () => pick(const PickLater()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: _ink,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            context.l10n.later,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pop-up's list from Home's places: Hem, Jobb, then the others.
List<PopupPlace> popupPlaces({
  String? home,
  String? work,
  required List<({String title, String type, String address})> others,
}) => [
  if ((home ?? '').trim().isNotEmpty)
    PopupPlace(
      kind: 'home',
      title: PlaceQuickSave.label('home'),
      address: home!,
    ),
  if ((work ?? '').trim().isNotEmpty)
    PopupPlace(
      kind: 'work',
      title: PlaceQuickSave.label('work'),
      address: work!,
    ),
  for (final o in others)
    if (o.address.trim().isNotEmpty)
      PopupPlace(
        kind: 'custom',
        title: o.title,
        address: o.address,
        type: o.type,
      ),
];
