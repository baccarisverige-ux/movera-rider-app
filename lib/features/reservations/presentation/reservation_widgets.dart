import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

const Color kReservationInk = Color(0xFF172127);
// UI-6: was 0xFF7B858B (3.77:1 on white); now ≥ 4.5:1 on kReservationSoft.
const Color kReservationMuted = Color(0xFF6A7278);
const Color kReservationLine = Color(0xFFE4E7E8);
const Color kReservationCta = Color(0xFF11181D);
const Color kReservationAccent = Color(0xFF356879);
const Color kReservationSoft = Color(0xFFF5F6F6);

TextStyle reservationText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = kReservationInk,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class ReservationRoutePreview extends StatelessWidget {
  const ReservationRoutePreview({
    super.key,
    required this.pickup,
    required this.destination,
    this.height = 148,
  });

  final String pickup;
  final String destination;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            Positioned(
              left: 14,
              top: 16,
              child: _pinLabel(destination, filled: true),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: _pinLabel(pickup, filled: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinLabel(String text, {required bool filled}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filled ? Icons.square_rounded : Icons.circle,
            size: filled ? 10 : 9,
            color: kReservationCta,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: reservationText(11.5, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EEF2),
    );
    final water = Paint()..color = const Color(0xFFD3E4EE);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-20, 8, size.width * 0.46, size.height * 0.7),
        const Radius.circular(80),
      ),
      water,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.55,
          size.height * 0.45,
          size.width * 0.6,
          90,
        ),
        const Radius.circular(40),
      ),
      water,
    );
    final land = Paint()..color = const Color(0xFFF4F1EA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.18,
          20,
          size.width * 0.7,
          size.height * 0.78,
        ),
        const Radius.circular(28),
      ),
      land,
    );
    final road = Paint()
      ..color = kReservationCta
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(28, size.height - 28)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.72,
        size.width * 0.42,
        size.height * 0.28,
        size.width - 36,
        28,
      );
    canvas.drawPath(path, road);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MoveraReserveBadge extends StatelessWidget {
  const MoveraReserveBadge({super.key, required this.when});

  final DateTime when;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: kReservationCta,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_available_rounded,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            ReservationFormat.time(when),
            style: reservationText(
              13,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class ReservationStatusBanner extends StatelessWidget {
  const ReservationStatusBanner({
    super.key,
    required this.title,
    required this.body,
    this.positive = true,
  });

  final String title;
  final String body;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final tone = positive ? const Color(0xFFEAF2F8) : const Color(0xFFF4F5F6);
    final dot = positive ? kReservationAccent : kReservationMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: reservationText(14.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: reservationText(
                    13,
                    color: kReservationMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReservationDriverBadge extends StatelessWidget {
  const ReservationDriverBadge({super.key, required this.ride});

  final Reservation ride;

  @override
  Widget build(BuildContext context) {
    final assigned = ride.driverAssigned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: assigned ? const Color(0xFFEAF2F8) : const Color(0xFFEEF1F3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ReservationFormat.driverBadge(ride),
        style: reservationText(
          11.5,
          weight: FontWeight.w600,
          color: assigned ? kReservationAccent : kReservationMuted,
        ),
      ),
    );
  }
}

/// UI-06: what happened to a finished ride ("Completed", "Ended early",
/// "Cancelled · fee 50 kr"), in the same pill as the driver badge.
class ReservationHistoryStatusChip extends StatelessWidget {
  const ReservationHistoryStatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('history-status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: reservationText(
          11.5,
          weight: FontWeight.w600,
          color: kReservationMuted,
        ),
      ),
    );
  }
}

class ReservationHistoryCard extends StatelessWidget {
  const ReservationHistoryCard({
    super.key,
    required this.ride,
    required this.onTap,
  });

  final Reservation ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kReservationLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 54,
                      height: 36,
                      child: Image.asset(
                        ride.categoryImage,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.directions_car_filled_rounded,
                          color: kReservationMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ride.categoryName,
                        style: reservationText(15, weight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      ReservationFormat.price(ride),
                      style: reservationText(14, weight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ReservationFormat.historyWhen(ride),
                  style: reservationText(13, color: kReservationMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ride.pickup.label} → ${ride.destination.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: reservationText(
                    13.5,
                    weight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                if (ReservationFormat.historyStatus(ride) case final status?)
                  ReservationHistoryStatusChip(label: status)
                else
                  ReservationDriverBadge(ride: ride),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReservationEditChip extends StatelessWidget {
  const ReservationEditChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: kReservationSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'Edit reservation',
                style: reservationText(13, weight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReservationEditButton extends StatelessWidget {
  const ReservationEditButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: kReservationInk,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          'Edit reservation',
          style: reservationText(
            14.5,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class ReservationFillButton extends StatelessWidget {
  const ReservationFillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: Material(
          color: kReservationCta,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: Text(
                label,
                style: reservationText(
                  15,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReservationGhostButton extends StatelessWidget {
  const ReservationGhostButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: Material(
          color: kReservationSoft,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: Text(
                label,
                style: reservationText(15, weight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReservationHeroArt extends StatelessWidget {
  const ReservationHeroArt({super.key, required this.asset, this.height = 148});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Image.asset(
          AppAssets.scheduleRideCar,
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class ReservationFact extends StatelessWidget {
  const ReservationFact({
    super.key,
    required this.asset,
    required this.label,
    required this.value,
    this.trailing,
  });

  final String asset;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoveraGlyph(asset: asset),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: reservationText(12, color: kReservationMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: reservationText(
                    15.5,
                    weight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class MoveraGlyph extends StatelessWidget {
  const MoveraGlyph({
    super.key,
    required this.asset,
    this.size = 32,
    this.glyph = 22,
  });

  final String asset;
  final double size;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColor.liteBlue,
      ),
      child: Image.asset(
        asset,
        height: glyph,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class ReservationPaymentMark extends StatelessWidget {
  const ReservationPaymentMark({
    super.key,
    required this.method,
    this.size = 36,
  });

  final String method;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lower = method.toLowerCase();
    Widget logo;
    Color background = Colors.white;
    if (lower.contains('apple')) {
      logo = SvgPicture.asset(
        'assets/images/apple_pay_brand.svg',
        fit: BoxFit.contain,
      );
    } else if (lower.contains('google')) {
      logo = Image.asset(
        'assets/images/google_pay_brand.png',
        fit: BoxFit.contain,
      );
    } else if (lower.contains('swish')) {
      logo = SvgPicture.asset(
        'assets/images/swish_brand.svg',
        fit: BoxFit.cover,
      );
    } else if (lower.contains('visa')) {
      logo = Image.asset(AppAssets.visa, fit: BoxFit.contain);
    } else if (lower.contains('master') || lower.contains('card')) {
      logo = Image.asset(AppAssets.mastercard, fit: BoxFit.contain);
    } else if (lower.contains('cash') || lower.contains('pay in car')) {
      background = const Color(0xFFEEF6F0);
      logo = const Icon(
        Icons.payments_outlined,
        color: Color(0xFF1F7A4D),
        size: 20,
      );
    } else {
      logo = Image.asset(AppAssets.wallet, fit: BoxFit.contain);
    }
    return Container(
      width: 42,
      height: 38,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: background == Colors.white ? kReservationLine : background,
        ),
      ),
      child: logo,
    );
  }
}
