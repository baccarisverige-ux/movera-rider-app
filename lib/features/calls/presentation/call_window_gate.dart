import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/messages/presentation/trip_call.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.113 BQ-S13 (owner 2026-11-01 "Keep call open for 1 hour but not
/// chat", Rules decisions/driver-g9.md:38; contract.json#inAppCalls.
/// callOpenUntil): a finished ride shows "Call driver" until the server's
/// `TripProjection.callOpenUntil` (drop-off + the country's "Call window
/// after the trip", default 60 min) and hides it by itself when that
/// passes. The trip is read once (`GET /trips/{tripId}`); no
/// `callOpenUntil` (calls off, the demo transport, a failed read) → no
/// button. The call is the in-app call (never a phone number); chat stays
/// closed.
class CallDriverAfterTrip extends StatefulWidget {
  const CallDriverAfterTrip({super.key, required this.rideId});

  final String? rideId;

  /// Reads the trip's projection; tests set their own. Null: the live
  /// client (nothing on the mock transport).
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(String tripId)? readTrip;

  static Future<Map<String, dynamic>?> _readLive(String tripId) async {
    final api = AppScope.instance.api;
    if (!api.contractWire) return null;
    return api.get(api.tripPath(tripId));
  }

  @override
  State<CallDriverAfterTrip> createState() => _CallDriverAfterTripState();
}

class _CallDriverAfterTripState extends State<CallDriverAfterTrip> {
  bool _open = false;
  Timer? _close;

  String get _id => widget.rideId?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    if (_id.isNotEmpty) unawaited(_read());
  }

  Future<void> _read() async {
    DateTime? until;
    try {
      final trip =
          await (CallDriverAfterTrip.readTrip ?? CallDriverAfterTrip._readLive)(
            _id,
          );
      final at = trip?['callOpenUntil'];
      until = at is String ? DateTime.tryParse(at) : null;
    } catch (error) {
      AppLog.warning(
        'trip_call.window_not_read',
        extra: {'rideId': _id, 'error': '$error'},
      );
    }
    final left = until?.difference(DateTime.now());
    if (!mounted || left == null || left.isNegative) return;
    setState(() => _open = true);
    _close = Timer(left, () {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _call() {
    SafetyController.shared.record(SafetyKind.maskedCall, rideId: _id);
    unawaited(
      callTripPeer(context, rideId: _id, transport: AppScope.instance.tripCall),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('call-driver-after-trip'),
          onPressed: _call,
          icon: const Icon(Icons.call),
          label: Text(context.l10n.callDriver),
        ),
      ),
    );
  }
}
