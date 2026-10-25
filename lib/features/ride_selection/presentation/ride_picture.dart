import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// What stands next to the car in a ride row (owner round 2).
enum RideExtra { none, priority, charger, paw, babySeat, icon }

/// The picture of a ride row, like the other ride apps: the same white car
/// for every type, the white van for the big ones, a slightly longer car for
/// Premium, and a small thing beside it that tells the type apart (a speed
/// gauge for Priority, a charger for Electric, a paw for Pet, a baby seat
/// for the child seat). Economy, Comfort and XL have nothing beside them.
class RidePicture extends StatelessWidget {
  const RidePicture({
    super.key,
    required this.rideId,
    this.glyph,
    this.glyphIcon,
  });

  final String rideId;

  /// The catalog's glyph key, for types the app has no rule for.
  final String? glyph;

  /// The icon a glyph key draws ([glyph] other than the known extras).
  final IconData? glyphIcon;

  static const car = 'assets/images/rides/car_white.webp';
  static const van = 'assets/images/rides/van_white.webp';
  static const charger = 'assets/images/rides/charger.svg';
  static const babySeat = 'assets/images/rides/baby_seat.svg';

  static const double width = 90;
  static const double height = 46;

  /// Types drawn as the van.
  static const _vanIds = {'xl', 'van', 'wheelchair'};

  /// Types with nothing beside the car.
  static const _plainIds = {'economy', 'comfort', 'xl', 'premium', 'van'};

  static bool isVan(String rideId, String? glyph) =>
      _vanIds.contains(rideId) || glyph == 'van' || glyph == 'wheelchair';

  /// Premium's car is drawn about 12 % longer, never taller.
  static bool isLong(String rideId) => rideId == 'premium';

  static RideExtra extraFor(String rideId, String? glyph) {
    switch (rideId) {
      case 'priority':
        return RideExtra.priority;
      case 'electric':
        return RideExtra.charger;
      case 'pet':
        return RideExtra.paw;
      case 'kids':
        return RideExtra.babySeat;
    }
    if (_plainIds.contains(rideId)) return RideExtra.none;
    switch (glyph) {
      case null:
      case 'car':
      case 'van':
        return RideExtra.none;
      case 'bolt':
        return RideExtra.charger;
      case 'pets':
        return RideExtra.paw;
      case 'child':
        return RideExtra.babySeat;
      default:
        return RideExtra.icon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asVan = isVan(rideId, glyph);
    final carWidth = asVan ? 70.0 : (isLong(rideId) ? 67.0 : 60.0);
    final carHeight = asVan ? 34.0 : 27.5;
    final extra = extraFor(rideId, glyph);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A soft shadow on the ground under the car.
          Positioned(
            right: carWidth * 0.08,
            bottom: 3,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(carWidth * 0.84, 6),
                painter: _GroundShadow(),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 5,
            width: carWidth,
            height: carHeight,
            child: Image.asset(
              asVan ? van : car,
              key: ValueKey('ride-picture-${asVan ? 'van' : 'car'}'),
              excludeFromSemantics: true,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_car_filled_rounded,
                color: Color(0xFF9AA4AA),
                size: 30,
              ),
            ),
          ),
          if (extra != RideExtra.none)
            Positioned(
              left: 0,
              bottom: 4,
              child: KeyedSubtree(
                key: ValueKey('ride-extra-${extra.name}'),
                child: _extra(extra),
              ),
            ),
        ],
      ),
    );
  }

  Widget _extra(RideExtra extra) {
    const ink = Color(0xFF1D252C);
    switch (extra) {
      case RideExtra.priority:
        return const Icon(Icons.speed_rounded, size: 19, color: ink);
      case RideExtra.paw:
        return const Icon(
          Icons.pets_rounded,
          size: 17,
          color: Color(0xFF111111),
        );
      case RideExtra.charger:
        return SvgPicture.asset(charger, width: 16, height: 23);
      case RideExtra.babySeat:
        return SvgPicture.asset(babySeat, width: 24, height: 19);
      case RideExtra.icon:
        return Icon(
          glyphIcon ?? Icons.directions_car_rounded,
          size: 17,
          color: ink,
        );
      case RideExtra.none:
        return const SizedBox.shrink();
    }
  }
}

class _GroundShadow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawOval(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
