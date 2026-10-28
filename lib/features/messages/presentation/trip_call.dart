import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the dialer with a number. A seam so tests never dial.
typedef TripCallDialer = Future<bool> Function(Uri uri);

Future<bool> _launchDialer(Uri uri) => launchUrl(uri);

/// Calls the driver through the trip's masked number (contract v0.13.0
/// §22): `POST /trips/{tripId}/call`, then the dialer with the
/// `proxyNumber`. The driver's real number is never asked for or shown.
/// Without a provider (`503 call_unavailable`, today) or without a transport
/// (the demo) the rider is told to use the chat; after drop-off
/// (`409 chat_closed`) the chat is marked closed.
Future<void> callTripPeer(
  BuildContext context, {
  required String? rideId,
  required TripCallTransport? transport,
  TripCallDialer dial = _launchDialer,
}) async {
  final id = rideId?.trim() ?? '';
  final unavailable = L10n.current.chatCallUnavailable;
  if (id.isEmpty || transport == null) {
    MoveraToast.show(context, unavailable);
    return;
  }
  try {
    final call = await transport.call(id);
    await dial(Uri(scheme: 'tel', path: call.proxyNumber));
  } catch (error) {
    AppLog.warning(
      'trip_call.failed',
      extra: {'rideId': id, 'error': error.toString()},
    );
    if (!context.mounted) return;
    if (error is ApiError && error.reason == 'chat_closed') {
      MessagesController.closeRide(id);
      MoveraToast.show(context, L10n.current.chatClosedAfterTrip);
      return;
    }
    MoveraToast.show(context, unavailable);
  }
}
