import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// How long the notice stays up. Long enough to read two short lines.
const Duration driverCancelledNoticeDuration = Duration(seconds: 6);

/// Tells the rider their driver dropped the ride while the search for a new
/// one is already running.
///
/// The rider is not asked anything: the ride is still on, so dispatch looks
/// again straight away. This used to be a sheet with a "Keep searching"
/// button, and nothing happened until the rider tapped it.
///
/// Shown on the app-wide messenger, so it stays up while the app moves back
/// to the search screen (or to the reservation) underneath it.
void showDriverCancelledNotice(BuildContext context, {String? driverName}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: DriverCancelledNotice(driverName: driverName),
        behavior: SnackBarBehavior.floating,
        duration: driverCancelledNoticeDuration,
        backgroundColor: const Color(0xFF1D252C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}

class DriverCancelledNotice extends StatelessWidget {
  const DriverCancelledNotice({super.key, this.driverName});

  final String? driverName;

  String get title =>
      driverName == null ? L10n.current.driverCancelled : L10n.current.nameCancelled(driverName!);

  static String get body => L10n.current.driverCancelledBody;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.autorenew_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.35,
                  color: const Color(0xFFD5DADE),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
