/// The server takes no ride reports yet (Audit Phase 5, P5-R7).
class RideDisputeNotServed implements Exception {
  const RideDisputeNotServed();

  @override
  String toString() => 'RideDisputeNotServed';
}
