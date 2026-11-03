import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.17 (owner BL-Q4): the rider's favourite drivers, marked
/// after a ride. A booked ride whose zone sends it to "Rider's favourites"
/// goes to them first.
class FavouriteDrivers {
  FavouriteDrivers(this._api);

  final ApiClient _api;
  static const path = '/api/v1/rider/favourite-drivers';

  /// The driver of trip [tripId] (from the server's trip), or null.
  Future<String?> driverOfTrip(String tripId) async {
    final trip = await _api.get('/api/v1/trips/${Uri.encodeComponent(tripId)}');
    final driver = trip['driver'];
    final id = driver is Map ? driver['driverId'] : null;
    return id is String && id.isNotEmpty ? id : null;
  }

  /// `PUT` marks, `DELETE` unmarks; the list after it.
  Future<List<String>> set(String driverId, {required bool favourite}) async {
    final answer = favourite
        ? await _api.put(
            '$path/${Uri.encodeComponent(driverId)}',
            body: const {},
          )
        : await _api.delete('$path/${Uri.encodeComponent(driverId)}');
    final items = answer['items'];
    return [
      if (items is List)
        for (final item in items)
          if (item is Map && item['driverId'] is String)
            item['driverId'] as String,
    ];
  }
}

/// "Save as a favourite driver" on the ride-completed screen (live only).
class FavouriteDriverToggle extends StatefulWidget {
  const FavouriteDriverToggle({super.key, required this.rideId, this.drivers});

  final String rideId;
  final FavouriteDrivers? drivers;

  @override
  State<FavouriteDriverToggle> createState() => _FavouriteDriverToggleState();
}

class _FavouriteDriverToggleState extends State<FavouriteDriverToggle> {
  bool _on = false;
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool next) async {
    final drivers = widget.drivers ?? FavouriteDrivers(AppScope.instance.api);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final driverId = await drivers.driverOfTrip(widget.rideId);
      if (driverId == null) throw StateError('no driver');
      final list = await drivers.set(driverId, favourite: next);
      if (mounted) setState(() => _on = list.contains(driverId));
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.favouriteDriverFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('favourite-driver'),
      value: _on,
      onChanged: _busy ? null : _toggle,
      title: Text(context.l10n.favouriteDriverTitle),
      subtitle: Text(_error ?? context.l10n.favouriteDriverHelp),
    );
  }
}
