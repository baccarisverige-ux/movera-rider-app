import 'package:flutter/material.dart';
import 'package:movera_rider/core/location/location_access_notice.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

/// Home's location recovery notice (UI-16), positioned just above the sheet.
///
/// Shown while [location] reports a refused/blocked permission, Location
/// Services off or only approximate location (rider-u114), and hidden again once a fix arrives. The rider can dismiss
/// it; a different problem shows it again. Must be a direct child of a
/// [Stack].
class HomeLocationNotice extends StatefulWidget {
  const HomeLocationNotice({
    super.key,
    required this.location,
    required this.bottom,
    required this.onRetry,
    this.onPrecise,
  });

  final HomeLocationController location;
  final double bottom;
  final VoidCallback onRetry;

  /// rider-u114: asks for precise location (the approximate-only notice).
  final VoidCallback? onPrecise;

  @override
  State<HomeLocationNotice> createState() => _HomeLocationNoticeState();
}

class _HomeLocationNoticeState extends State<HomeLocationNotice> {
  LocationAccessIssue? _dismissed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.location,
      builder: (context, _) {
        final issue = widget.location.accessIssue;
        if (issue == null || issue == _dismissed) {
          return const SizedBox.shrink();
        }
        return Positioned(
          left: 16,
          right: 16,
          bottom: widget.bottom + 14,
          child: LocationAccessNotice(
            issue: issue,
            onRetry: widget.onRetry,
            onPrecise: widget.onPrecise,
            onDismiss: () => setState(() => _dismissed = issue),
          ),
        );
      },
    );
  }
}
