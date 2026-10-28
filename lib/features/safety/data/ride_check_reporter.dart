import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';

/// The rider's answer on the wire (contract v0.12.0 §22).
enum RideCheckWireAnswer {
  ok('ok'),
  needHelp('need_help');

  const RideCheckWireAnswer(this.wire);
  final String wire;
}

/// `RideCheckReceipt` from movera-server.
class RideCheckReportReceipt {
  const RideCheckReportReceipt({
    required this.checkId,
    this.answer,
    this.incidentId,
  });

  factory RideCheckReportReceipt.fromJson(
    Map<String, dynamic> json,
    String checkId,
  ) => RideCheckReportReceipt(
    checkId: json['checkId'] as String? ?? checkId,
    answer: json['answer'] as String?,
    incidentId: json['incidentId'] as String?,
  );

  final String checkId;
  final String? answer;
  final String? incidentId;
}

/// Contract v0.12.0 §22: `POST /rider/trips/{tripId}/ride-check`. The app
/// reports a check once when the card shows (no answer; Movera's 2-minute
/// clock starts) and once with the answer. One Idempotency-Key per report,
/// kept for every retry.
class RideCheckReporter {
  RideCheckReporter(
    this._api, {
    Future<void> Function(Duration)? sleep,
    Future<SosPosition?> Function()? locate,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _locate = locate ?? lastSosPosition;

  final ApiClient _api;
  final Future<void> Function(Duration) _sleep;
  final Future<SosPosition?> Function() _locate;

  static const retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// The receipt, or null when the trip no longer takes checks (409).
  /// Throws the last error when every try failed.
  Future<RideCheckReportReceipt?> report({
    required String tripId,
    required String checkId,
    required RideCheckTrigger trigger,
    required DateTime at,
    RideCheckWireAnswer? answer,
  }) async {
    final key = newIdempotencyKey('ride-check');
    SosPosition? position;
    try {
      position = await _locate();
    } catch (_) {
      position = null;
    }
    final body = <String, dynamic>{
      'checkId': checkId,
      'trigger': trigger.wire,
      'at': at.toUtc().toIso8601String(),
      if (answer != null) 'answer': answer.wire,
      if (position != null) 'position': position.toJson(),
    };
    final path =
        '/api/v1/rider/trips/${Uri.encodeComponent(tripId)}/ride-check';
    for (var attempt = 0; ; attempt++) {
      try {
        final json = await _api.post(path, body: body, idempotencyKey: key);
        return RideCheckReportReceipt.fromJson(json, checkId);
      } on ApiError catch (error) {
        if (error.statusCode == 409 || error.code == 'invalid_transition') {
          return null;
        }
        if (!_retryable(error) || attempt >= retryDelays.length) rethrow;
        await _sleep(retryDelays[attempt]);
      } on Exception {
        if (attempt >= retryDelays.length) rethrow;
        await _sleep(retryDelays[attempt]);
      }
    }
  }

  static bool _retryable(ApiError error) =>
      error.code == 'NETWORK' ||
      error.code == 'TIMEOUT' ||
      error.code == 'rate_limited' ||
      error.code == 'unavailable' ||
      (error.statusCode != null && error.statusCode! >= 500);
}
