import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/short_address.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The horizontally-scrolling Home / Work / Add / custom-place row.
class SavedPlacesRow extends StatelessWidget {
  const SavedPlacesRow({
    super.key,
    required this.homeAddress,
    required this.workAddress,
    required this.savedPlaces,
    required this.onUseSavedPlace,
    required this.onAddPlace,
    this.onEditSavedPlace,
    this.onEditCustomPlace,
    this.reveal = 1,
  });

  final String? homeAddress;
  final String? workAddress;
  final List<SavedPlaceData> savedPlaces;
  final void Function(
    String? address, {
    required String target,
    String? customType,
  })
  onUseSavedPlace;
  final VoidCallback onAddPlace;

  /// Long-press on a place to change its address.
  final void Function(String target, {String? customType})? onEditSavedPlace;

  /// Long-press on a custom place: change that place's address. Several
  /// places can share a kind, so it is named by the place itself
  /// (rider-41). Without it the long-press falls back to [onEditSavedPlace].
  final void Function(SavedPlaceData place)? onEditCustomPlace;

  /// 0 → hidden, 1 → shown. The cards come in one after the other.
  final double reveal;

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.5);
    final t = ((reveal - start) / (1 - start)).clamp(0.0, 1.0);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      SizedBox(
        width: ResSize.w * 108,
        child: _QuickPlaceCard(
          iconAsset: AppAssets.solarHome,
          title: context.l10n.placeHome,
          subtitle: homeAddress == null
              ? context.l10n.placeSetHome
              : shortAddress(homeAddress, maxLength: 15),
          onTap: () => onUseSavedPlace(homeAddress, target: 'home'),
          onLongPress: onEditSavedPlace == null
              ? null
              : () => onEditSavedPlace!('home'),
        ),
      ),
      8.width,
      SizedBox(
        width: ResSize.w * 108,
        child: _QuickPlaceCard(
          iconAsset: AppAssets.solarCase,
          title: context.l10n.placeWork,
          subtitle: workAddress == null
              ? context.l10n.placeSetWork
              : shortAddress(workAddress, maxLength: 15),
          onTap: () => onUseSavedPlace(workAddress, target: 'work'),
          onLongPress: onEditSavedPlace == null
              ? null
              : () => onEditSavedPlace!('work'),
        ),
      ),
      8.width,
      SizedBox(
        width: ResSize.w * 108,
        child: _QuickPlaceCard(
          iconAsset: AppAssets.solarAdd,
          title: context.l10n.placeAdd,
          subtitle: context.l10n.placeNew,
          onTap: onAddPlace,
        ),
      ),
    ];
    for (final place in savedPlaces) {
      cards
        ..add(8.width)
        ..add(
          SizedBox(
            width: ResSize.w * 108,
            child: _CustomPlaceCard(
              place: place,
              onTap: () => onUseSavedPlace(
                place.address,
                target: 'custom',
                customType: place.type,
              ),
              onLongPress: onEditCustomPlace != null
                  ? () => onEditCustomPlace!(place)
                  : onEditSavedPlace == null
                  ? null
                  : () => onEditSavedPlace!('custom', customType: place.type),
            ),
          ),
        );
    }
    // UI-2: a minimum, not a fixed height, so large text grows the row.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: ResSize.h * 46),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++)
              _staggered((i + 1) ~/ 2, cards[i]),
          ],
        ),
      ),
    );
  }
}

/// Solar linear icon for a saved-place type, matching the Home chips.
String placeIconAssetFor(String type) {
  switch (type) {
    case 'gym':
      return AppAssets.solarGym;
    case 'mall':
      return AppAssets.solarMall;
    case 'school':
      return AppAssets.solarSchool;
    case 'airport':
      return AppAssets.solarPlane;
    case 'family':
      return AppAssets.solarFamily;
    case 'restaurant':
      return AppAssets.solarRestaurant;
    default:
      return AppAssets.solarMapPoint;
  }
}

/// rider-42: what a custom place is called on screen. A place saved from
/// Home without a name stores its type key as the title ("gym"); that is
/// shown as the type's label in the app language.
String savedPlaceTitle(String title, String type) {
  final clean = title.trim();
  return clean.isEmpty || clean == type ? placeLabelFor(type) : clean;
}

/// Label for a custom saved place type ("gym" → "Gym").
String placeLabelFor(String type) {
  switch (type) {
    case 'gym':
      return L10n.current.placeGym;
    case 'mall':
      return L10n.current.placeMall;
    case 'school':
      return L10n.current.placeSchool;
    case 'airport':
      return L10n.current.placeAirport;
    case 'family':
      return L10n.current.placeFamily;
    case 'restaurant':
      return L10n.current.placeRestaurant;
    default:
      return L10n.current.placeOther;
  }
}

IconData _placeIcon(String type) {
  switch (type) {
    case 'gym':
      return Icons.fitness_center_rounded;
    case 'mall':
      return Icons.local_mall_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'airport':
      return Icons.flight_takeoff_rounded;
    case 'family':
      return Icons.family_restroom_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    default:
      return Icons.place_outlined;
  }
}

class _CustomPlaceCard extends StatelessWidget {
  const _CustomPlaceCard({
    required this.place,
    required this.onTap,
    this.onLongPress,
  });

  static const Color _premiumInk = Color(0xFF1D252C);
  static const Color _premiumMuted = Color(0xFF5C656C);
  static const Color _premiumAccent = Color(0xFF2D5878);

  final SavedPlaceData place;
  final VoidCallback? onLongPress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: BoxConstraints(minHeight: ResSize.h * 44),
          padding: EdgeInsets.symmetric(horizontal: ResSize.w * 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF5F9F9)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE7E9), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(
                _placeIcon(place.type),
                size: ResSize.h * 13,
                color: _premiumAccent,
              ),
              7.width,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextWidget(
                      text: savedPlaceTitle(place.title, place.type),
                      color: _premiumInk,
                      fontSize: 10.5,
                      fontWeight: fwSemiBold,
                    ),
                    2.height,
                    TextWidget(
                      text: shortAddress(place.address, maxLength: 15),
                      // UI-6: full strength (the 0.82 alpha gave 3.96:1).
                      color: _premiumMuted,
                      fontSize: 7.8,
                      fontWeight: fwNormal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPlaceCard extends StatelessWidget {
  const _QuickPlaceCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  static const Color _premiumInk = Color(0xFF1D252C);
  static const Color _premiumMuted = Color(0xFF5C656C);

  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(minHeight: ResSize.h * 44),
          padding: EdgeInsets.symmetric(horizontal: ResSize.w * 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF5F9F9)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE7E9), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF174E55).withValues(alpha: 0.055),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: AppColor.white.withValues(alpha: 0.9),
                blurRadius: 2,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            children: [
              AppIconAsset(
                iconAsset,
                size: ResSize.w * 12.3,
                color: const Color(0xFF1D252C),
              ),
              8.width,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextWidget(
                      text: title,
                      color: _premiumInk,
                      fontSize: 11.5,
                      fontWeight: fwSemiBold,
                    ),
                    2.height,
                    TextWidget(
                      text: subtitle,
                      // UI-6: full strength (the 0.82 alpha gave 3.96:1).
                      color: _premiumMuted,
                      fontSize: 8.25,
                      fontWeight: fwNormal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
