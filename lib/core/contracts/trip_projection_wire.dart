/// The trip projection inside a `GET` trip answer.
///
/// Contract v0.3 §1: a success response is the bare `TripProjection`. The
/// pre-v0.3 `{code, ride}` envelope is still read during the migration.
/// Null when the answer holds neither.
Map<String, dynamic>? tripProjectionOf(Map<String, dynamic> json) {
  final ride = json['ride'];
  if (ride is Map) return Map<String, dynamic>.from(ride);
  if (json['status'] != null) return json;
  return null;
}

/// The trip id of a projection: contract `tripId`, else the legacy `id` or
/// `rideId` alias. Null when blank.
String? tripIdOf(Map<dynamic, dynamic> projection) {
  final raw = projection['tripId'] ?? projection['id'] ?? projection['rideId'];
  final id = raw?.toString().trim();
  return id == null || id.isEmpty ? null : id;
}
