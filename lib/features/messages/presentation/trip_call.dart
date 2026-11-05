import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/calls/application/rider_trip_calls.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the dialer with a number. A seam so tests never dial.
typedef TripCallDialer = Future<bool> Function(Uri uri);

Future<bool> _launchDialer(Uri uri) => launchUrl(uri);

/// Calls the driver. v0.18.38 §62 (fix job 8, owner G15 2026-11-05
/// "In-app calls only", "Both rider and driver", "Just 'Call failed'"):
/// `POST /trips/{tripId}/call` answers `mode: in_app` and the in-app call
/// screen opens (WebRTC). Only a country on a phone company answers
/// `mode: phone`; then the dialer opens with the masked `proxyNumber`
/// (contract v0.13.0). A call that cannot start says only "Call failed".
/// The driver's real number is never asked for or shown.
Future<void> callTripPeer(
  BuildContext context, {
  required String? rideId,
  required TripCallTransport? transport,
  RiderTripCalls? calls,
  String? driverName,
  TripCallDialer dial = _launchDialer,
  void Function(String text)? onSay,
}) async {
  // In Chat the text shows above the write field ([onSay]) so it never
  // covers the field or the send button (G9 live 2026-11-02).
  void say(String text) =>
      onSay != null ? onSay(text) : MoveraToast.show(context, text);
  final id = rideId?.trim() ?? '';
  final failed = L10n.current.callFailed;
  if (id.isEmpty || transport == null) {
    say(failed);
    return;
  }
  final TripCall call;
  try {
    call = await transport.call(id);
  } catch (error) {
    AppLog.warning(
      'trip_call.failed',
      extra: {'rideId': id, 'error': error.toString()},
    );
    if (!context.mounted) return;
    // An older server closed calls with the chat at drop-off.
    if (error is ApiError && error.reason == 'chat_closed') {
      MessagesController.closeRide(id);
      say(L10n.current.chatClosedAfterTrip);
      return;
    }
    say(failed);
    return;
  }
  final proxy = call.proxyNumber;
  if (!call.inApp) {
    if (proxy != null) {
      await dial(Uri(scheme: 'tel', path: proxy));
    } else if (context.mounted) {
      say(failed);
    }
    return;
  }
  final hub =
      calls ??
      RiderTripCalls.instance ??
      (transport is CallApi ? RiderTripCalls(api: transport as CallApi) : null);
  if (hub == null) {
    if (context.mounted) say(failed);
    return;
  }
  final session = hub.outgoing(id);
  await session.begin(call.toJson());
  if (!context.mounted) return;
  await TripCallScreen.open(context, session, name: driverName);
}
