import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/ride_check_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/l10n/l10n.dart';

const _ink = Color(0xFF1D252C);
const _muted = Color(0xFF5C656C);
const _well = Color(0xFFF4F4F4);
const _alert = Color(0xFFB42318);

/// RC5: the "Ride check" entry in a trip's details and history, with when it
/// opened, why, and what the rider answered. Shows nothing for a trip that
/// had no Ride check.
class RideCheckTripEntry extends StatefulWidget {
  const RideCheckTripEntry({
    super.key,
    required this.rideId,
    this.service,
    this.changes,
    this.topSpacing = 12,
  });

  final String? rideId;
  final RideCheckService? service;

  /// Reloads when this fires (a Ride check was answered); defaults to the
  /// app's Ride check.
  final Listenable? changes;

  /// Space above the entry when there is one.
  final double topSpacing;

  @override
  State<RideCheckTripEntry> createState() => _RideCheckTripEntryState();
}

class _RideCheckTripEntryState extends State<RideCheckTripEntry> {
  late Future<List<RideCheckRecord>> _records = _load();
  late final Listenable _changes = widget.changes ?? RideCheckController.shared;

  @override
  void initState() {
    super.initState();
    _changes.addListener(_reload);
  }

  @override
  void dispose() {
    _changes.removeListener(_reload);
    super.dispose();
  }

  /// Kept while a reload runs, so the entry does not blink.
  List<RideCheckRecord>? _last;

  void _reload() {
    if (!mounted) return;
    final next = _load();
    setState(() {
      _records = next;
    });
  }

  Future<List<RideCheckRecord>> _load() async {
    final id = widget.rideId?.trim();
    if (id == null || id.isEmpty) return const [];
    final service = widget.service ?? SafetyController.shared.rideCheck;
    try {
      return await service.records(id);
    } catch (_) {
      // The trip's details still show; the entry is left out.
      return const [];
    }
  }

  @override
  void didUpdateWidget(covariant RideCheckTripEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideId != widget.rideId) _records = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RideCheckRecord>>(
      future: _records,
      initialData: _last,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <RideCheckRecord>[];
        _last = records;
        if (records.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: widget.topSpacing),
          child: Column(
            key: const ValueKey<String>('ride-check-trip-entry'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final record in records) _RecordTile(record: record),
            ],
          ),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final RideCheckRecord record;

  @override
  Widget build(BuildContext context) {
    final local = record.shownAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    TextStyle style(
      double size, {
      FontWeight weight = FontWeight.w400,
      Color color = _ink,
    }) => GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.4,
    );
    return Semantics(
      container: true,
      label: context.l10n.rcEntrySemantics(
        time,
        record.trigger.label,
        record.answerSummary,
      ),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _well,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: AppIconAsset(
                AppAssets.solarShieldWarning,
                size: 18,
                color: record.alerted ? _alert : _ink,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.rcRideCheck,
                    style: style(14.5, weight: FontWeight.w600),
                  ),
                  Text(
                    '$time · ${record.trigger.label}',
                    style: style(12.5, color: _muted),
                  ),
                  const SizedBox(height: 4),
                  Text(record.answerSummary, style: style(13)),
                  if (record.alerted)
                    Text(
                      context.l10n.rcAlertSentTitle,
                      style: style(12, weight: FontWeight.w600, color: _alert),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
