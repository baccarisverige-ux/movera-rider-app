import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// `payload.kind` of a safety event that is a Ride check.
const rideCheckEventKind = 'ridecheck';

/// A Ride check event: one this app opened, or a trigger event the server
/// posted to the ride (an SOS or a manual check is not one).
bool isRideCheckEvent(RideCheckEvent event) {
  final kind = event.payload['kind'];
  if (kind == rideCheckEventKind) return true;
  if (kind != null) return false;
  return switch (event.type) {
    RideCheckEventType.unexpectedStop ||
    RideCheckEventType.routeDeviation ||
    RideCheckEventType.destinationPassed ||
    RideCheckEventType.movementLost ||
    RideCheckEventType.possibleCrash ||
    RideCheckEventType.droppedFar => true,
    RideCheckEventType.manualSafetyCheck ||
    RideCheckEventType.resolved => false,
  };
}

enum RideCheckAnswerKind { ok, call112, row, question, note }

/// One thing the rider answered on the card, in the order they did it.
class RideCheckAnswer {
  const RideCheckAnswer({
    required this.kind,
    required this.id,
    required this.label,
    required this.at,
    this.value,
    this.question,
  });

  factory RideCheckAnswer.ok(DateTime at) => RideCheckAnswer(
    kind: RideCheckAnswerKind.ok,
    id: 'ok',
    label: "I'm OK",
    at: at,
  );

  factory RideCheckAnswer.call112(DateTime at) => RideCheckAnswer(
    kind: RideCheckAnswerKind.call112,
    id: 'call_112',
    label: 'Called 112',
    at: at,
  );

  factory RideCheckAnswer.row(RideCheckRow row, DateTime at) => RideCheckAnswer(
    kind: RideCheckAnswerKind.row,
    id: row.wire,
    label: row.label,
    at: at,
  );

  factory RideCheckAnswer.question(
    RideCheckQuestion question,
    RideCheckOption option,
    DateTime at,
  ) => RideCheckAnswer(
    kind: RideCheckAnswerKind.question,
    id: question.id,
    label: option.label,
    value: rideCheckOptionWire(option.id),
    question: question.text,
    at: at,
  );

  factory RideCheckAnswer.note(String text, DateTime at) => RideCheckAnswer(
    kind: RideCheckAnswerKind.note,
    id: 'note',
    label: text,
    at: at,
  );

  final RideCheckAnswerKind kind;

  /// `ok`, `call_112`, the row's wire id, the question id or `note`.
  final String id;
  final String label;
  final DateTime at;

  /// A question's chosen option (`yes`, `not_sure`, ...).
  final String? value;
  final String? question;

  /// "Is anyone hurt? Yes", or the row / action label, in the app
  /// language (the saved [label] and [question] stay as they were sent).
  String get summary => switch (kind) {
    RideCheckAnswerKind.ok => L10n.current.rcImOk,
    RideCheckAnswerKind.call112 => L10n.current.rcCalled112,
    RideCheckAnswerKind.row => _rowLabel(id) ?? label,
    RideCheckAnswerKind.question =>
      '${rideCheckQuestionText(id) ?? question ?? id} '
          '${rideCheckOptionText(value ?? '') ?? label}',
    RideCheckAnswerKind.note => '“$label”',
  };

  static String? _rowLabel(String wire) {
    for (final row in rideCheckAllRows) {
      if (row.wire == wire) return row.displayLabel;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'label': label,
    'at': at.toUtc().toIso8601String(),
    if (value != null) 'value': value,
    if (question != null) 'question': question,
  };

  static RideCheckAnswer? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = RideCheckAnswerKind.values.where(
      (value) => value.name == raw['kind'],
    );
    final id = raw['id'];
    final label = raw['label'];
    if (kind.isEmpty || id is! String || label is! String) return null;
    return RideCheckAnswer(
      kind: kind.first,
      id: id,
      label: label,
      at:
          DateTime.tryParse('${raw['at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      value: raw['value'] is String ? raw['value'] as String : null,
      question: raw['question'] is String ? raw['question'] as String : null,
    );
  }
}

String rideCheckOptionWire(RideCheckOptionId id) => switch (id) {
  RideCheckOptionId.yes => 'yes',
  RideCheckOptionId.no => 'no',
  RideCheckOptionId.notSure => 'not_sure',
  RideCheckOptionId.me => 'me',
  RideCheckOptionId.driver => 'the_driver',
  RideCheckOptionId.someoneElse => 'someone_else',
};

class RideCheckPlace {
  const RideCheckPlace({required this.label, this.point});

  final String label;
  final GeoPoint? point;

  Map<String, dynamic> toJson() => {
    'label': label,
    if (point != null) 'lat': point!.latitude,
    if (point != null) 'lng': point!.longitude,
  };
}

/// Who and what the alert is about: the rider, the driver and the trip
/// (RC4 sends all three to admin and Dispatch).
class RideCheckTripContext {
  const RideCheckTripContext({
    required this.rideId,
    this.riderName,
    this.riderPhone,
    this.riderId = 'rider-local',
    this.driverId,
    this.driverName,
    this.driverPlate,
    this.driverVehicle,
    this.pickup,
    this.destination,
    this.stops = const [],
    this.rideType,
    this.status,
    this.lastLocation,
    this.lastLocationAt,
  });

  final String rideId;
  final String riderId;
  final String? riderName;
  final String? riderPhone;
  final String? driverId;
  final String? driverName;
  final String? driverPlate;
  final String? driverVehicle;
  final RideCheckPlace? pickup;
  final RideCheckPlace? destination;
  final List<RideCheckPlace> stops;
  final String? rideType;
  final String? status;
  final GeoPoint? lastLocation;
  final DateTime? lastLocationAt;

  RideCheckTripContext copyWith({
    String? driverId,
    String? driverName,
    String? driverPlate,
    String? driverVehicle,
    RideCheckPlace? destination,
    List<RideCheckPlace>? stops,
    String? status,
    GeoPoint? lastLocation,
    DateTime? lastLocationAt,
  }) {
    return RideCheckTripContext(
      rideId: rideId,
      riderId: riderId,
      riderName: riderName,
      riderPhone: riderPhone,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      driverPlate: driverPlate ?? this.driverPlate,
      driverVehicle: driverVehicle ?? this.driverVehicle,
      pickup: pickup,
      destination: destination ?? this.destination,
      stops: stops ?? this.stops,
      rideType: rideType,
      status: status ?? this.status,
      lastLocation: lastLocation ?? this.lastLocation,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    );
  }

  Map<String, dynamic> riderJson() => {
    'id': riderId,
    if (riderName != null) 'name': riderName,
    if (riderPhone != null) 'phone': riderPhone,
  };

  Map<String, dynamic> driverJson() => {
    if (driverId != null) 'id': driverId,
    if (driverName != null) 'name': driverName,
    if (driverPlate != null) 'plate': driverPlate,
    if (driverVehicle != null) 'vehicle': driverVehicle,
  };

  Map<String, dynamic> tripJson() => {
    'rideId': rideId,
    if (pickup != null) 'pickup': pickup!.toJson(),
    if (destination != null) 'destination': destination!.toJson(),
    if (stops.isNotEmpty) 'stops': [for (final stop in stops) stop.toJson()],
    if (rideType != null) 'rideType': rideType,
    if (status != null) 'status': status,
    if (lastLocation != null)
      'lastLocation': {
        'lat': lastLocation!.latitude,
        'lng': lastLocation!.longitude,
        if (lastLocationAt != null)
          'at': lastLocationAt!.toUtc().toIso8601String(),
      },
  };
}

/// The body of `POST /api/v1/safety/ridecheck/answers`. It never carries an
/// audio recording: those stay on the rider's phone (RC5).
class RideCheckSubmission {
  const RideCheckSubmission({
    required this.checkId,
    required this.trigger,
    required this.shownAt,
    required this.answers,
    required this.context,
    this.reason = const RideCheckReason(),
    this.alert = false,
    this.alertId,
    this.isFinal = false,
  });

  final String checkId;
  final RideCheckTrigger trigger;
  final DateTime shownAt;
  final List<RideCheckAnswer> answers;
  final RideCheckTripContext context;
  final RideCheckReason reason;

  /// True once the answers mean the safety team must be alerted.
  final bool alert;

  /// Set when this updates an alert already sent.
  final String? alertId;

  /// The card is closed: these are all the answers.
  final bool isFinal;

  Map<String, dynamic> toJson() => {
    'checkId': checkId,
    'rideId': context.rideId,
    'trigger': trigger.wire,
    'shownAt': shownAt.toUtc().toIso8601String(),
    'reason': reason.toJson(),
    'answers': [for (final answer in answers) answer.toJson()],
    'alert': alert,
    if (alertId != null) 'alertId': alertId,
    'final': isFinal,
    'rider': context.riderJson(),
    'driver': context.driverJson(),
    'trip': context.tripJson(),
  };
}

/// What the server said back to a submission.
class RideCheckReceipt {
  const RideCheckReceipt({
    required this.checkId,
    this.alertId,
    this.alertStatus,
    this.recipients = const [],
  });

  final String checkId;
  final String? alertId;

  /// `sent` the first time, `updated` after.
  final String? alertStatus;
  final List<String> recipients;

  bool get alerted => alertId != null;

  factory RideCheckReceipt.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'];
    final alert = json['alert'];
    final checkId = answer is Map ? '${answer['checkId'] ?? ''}' : '';
    if (alert is! Map) return RideCheckReceipt(checkId: checkId);
    final recipients = alert['recipients'];
    return RideCheckReceipt(
      checkId: checkId,
      alertId: alert['alertId'] is String ? alert['alertId'] as String : null,
      alertStatus: alert['status'] is String ? alert['status'] as String : null,
      recipients: recipients is List
          ? [for (final item in recipients) '$item']
          : const [],
    );
  }
}

/// A Ride check as the trip's details show it (RC5): when, why and what the
/// rider answered.
class RideCheckRecord {
  const RideCheckRecord({
    required this.checkId,
    required this.rideId,
    required this.trigger,
    required this.shownAt,
    this.answers = const [],
    this.alerted = false,
  });

  final String checkId;
  final String rideId;
  final RideCheckTrigger trigger;
  final DateTime shownAt;
  final List<RideCheckAnswer> answers;
  final bool alerted;

  bool get answered => answers.isNotEmpty;

  /// "I'm OK", or every answer joined: "There was an accident · Is anyone
  /// hurt? Yes".
  String get answerSummary => answered
      ? answers.map((answer) => answer.summary).join(' · ')
      : L10n.current.rcNoAnswerYet;

  /// Null when [event] is not a Ride check.
  static RideCheckRecord? fromEvent(RideCheckEvent event) {
    final payload = event.payload;
    if (!isRideCheckEvent(event)) return null;
    final trigger =
        parseRideCheckTrigger(
          payload['trigger'] is String ? payload['trigger'] as String : null,
        ) ??
        parseRideCheckTrigger(event.type.name);
    if (trigger == null) return null;
    final raw = payload['answers'];
    final answers = <RideCheckAnswer>[
      if (raw is List)
        for (final item in raw) ?RideCheckAnswer.tryParse(item),
    ];
    return RideCheckRecord(
      checkId: event.eventId,
      rideId: event.rideId,
      trigger: trigger,
      shownAt: event.at,
      answers: answers,
      alerted: payload['alertId'] is String,
    );
  }
}
