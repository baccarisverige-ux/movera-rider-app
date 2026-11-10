part of 'select_ride.dart';

/// Owner 2026-11-10 (contract §21): the zone list kept on the device can be
/// older than the server's. Before "not here" the list is read again once
/// per pickup; the server stays the final judge (a quote answered
/// `service_not_available` is "not here" whatever the list says).
class _ZoneRecheck {
  /// The pickup the list was last read again for.
  LatLng? checkedFor;
  bool running = false;

  /// Whether the pickup was served the last time the list changed; null
  /// before any list was known.
  bool? servedSeen;
}

extension _SelectRideZones on _SelectRideState {
  bool get _pickupServedHere =>
      RiderZones.serves(_pickupPosition.latitude, _pickupPosition.longitude);

  /// The device list leaves the pickup out: "Checking your area…" while the
  /// list is read again, null once the fresh list still leaves it out.
  Widget? _zoneRecheckGate() {
    final pickup = _pickupPosition;
    if (_zoneRecheck.checkedFor == pickup && !_zoneRecheck.running) {
      return null;
    }
    if (!_zoneRecheck.running) {
      _zoneRecheck.running = true;
      Future<void>.microtask(() async {
        try {
          await _zones.refresh();
        } finally {
          _zoneRecheck
            ..running = false
            ..checkedFor = pickup;
          // ignore: invalid_use_of_protected_member
          if (mounted) setState(() {});
        }
      });
    }
    return CheckingAreaView(zones: _zones);
  }

  /// The zone list changed (first known, a resume, a publish, a retry):
  /// rebuild, and price again when the pickup's zone or currency moved.
  void _onZonesChanged() {
    if (!mounted || !RiderZones.known) return;
    final currency = RiderZones.at(
      _pickupPosition.latitude,
      _pickupPosition.longitude,
    ).currency;
    final served = _pickupServedHere;
    final reprice =
        currency != _selection.currency || served != _zoneRecheck.servedSeen;
    _zoneRecheck.servedSeen = served;
    // ignore: invalid_use_of_protected_member
    setState(() => _selection.currency = currency);
    if (reprice) {
      unawaited(_loadQuotes());
      unawaited(_loadZoneConfig());
    }
  }
}
