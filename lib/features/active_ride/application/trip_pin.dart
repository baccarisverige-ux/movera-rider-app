import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// G6 (contract v0.18.8): `GET /trips/{tripId}/pin` → `PinCode { tripId,
/// pin, expiresAt }`. Null when the trip has no PIN (404
/// `pin_not_required`) or the call failed.
Future<String?> fetchTripPin(ApiClient api, String tripId) async {
  try {
    final body = await api.get(
      '/api/v1/trips/${Uri.encodeComponent(tripId)}/pin',
    );
    final pin = body['pin'];
    return pin is String && RegExp(r'^\d{4}$').hasMatch(pin) ? pin : null;
  } catch (error) {
    AppLog.warning('trip_pin.fetch_failed', extra: {'error': '$error'});
    return null;
  }
}

/// `arrivedWaiting.alerts.texts.riderPaid` / `riderNoShow` (time only, no
/// amounts; owner decisions 4 and 6).
String waitingAlertText(AppLocalizations l10n, String kind) =>
    kind == alertNoShowPossible
    ? l10n.waitingAlertNoShow
    : l10n.waitingAlertPaid;
