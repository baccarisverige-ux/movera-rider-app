import 'dart:async';

import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Adapts the authoritative local reservation lifecycle to the shared active
/// ride presentation without inventing a second on-demand ride.
///
/// The backend can later replace the ReservationController source while this
/// presentation contract stays unchanged.
class ReservationRideRealtime implements RideRealtime {
  ReservationRideRealtime({
    required this.controller,
    required this.reservationId,
  });

  final ReservationController controller;
  final String reservationId;

  @override
  bool get supportsRiderSignals => false;

  bool _disposed = false;
  int _sequence = 0;
  ReservationStatus? _lastReservationStatus;

  static MatchedDriver driverOf(ReservationDriver driver) {
    final parts = (driver.vehicle ?? '')
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return MatchedDriver(
      id: 'rsv-driver-${driver.firstName}',
      firstName: driver.firstName,
      rating: driver.rating,
      vehicleMake: parts.isNotEmpty ? parts.first : driver.vehicle,
      vehicleModel: parts.length > 1 ? parts.sublist(1).join(' ') : null,
      plate: driver.plate,
      photoAsset: driver.photoAsset,
    );
  }

  // ARCH-10: one reservation -> ride map (ReservationStatusAsTripStatus in
  // the reservation domain). A scheduled reservation is bookingRequested until
  // dispatch starts, not findingDriver.
  RideStatus _mapStatus(ReservationStatus status) {
    if (status == ReservationStatus.cancelled) {
      // The reservation record does not encode who cancelled it. A rider
      // initiated cancel is handled synchronously by the screen callback;
      // an unsolicited cancelled record is therefore treated as external.
      return RideStatus.cancelledBySystem;
    }
    return status.asRideStatus;
  }

  RideRealtimeEvent? _eventForCurrent() {
    if (_disposed) return null;
    final ride = controller.byId(reservationId);
    if (ride == null) return null;

    final previous = _lastReservationStatus;
    final current = ride.status;
    _lastReservationStatus = current;

    var status = _mapStatus(current);
    RideRealtimeSignal? signal;
    String? message;

    // A scheduled driver can drop the reservation while it remains valid.
    // Surface that as the same transient driver-cancel event used by Book Now,
    // then return the rider to the reservation/searching surface.
    if (previous != null &&
        previous.hasDriver &&
        current == ReservationStatus.driverAssignmentPending) {
      status = RideStatus.cancelledByDriver;
    } else if (current == ReservationStatus.driverArrived) {
      signal = RideRealtimeSignal.driverArrived;
      message = 'Your driver has arrived at the pickup point.';
    }

    _sequence += 1;
    return RideRealtimeEvent(
      rideId: reservationId,
      status: status,
      sequence: _sequence,
      at: DateTime.now(),
      driver: ride.driver == null ? null : driverOf(ride.driver!),
      signal: signal,
      message: message,
    );
  }

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    return Stream<RideRealtimeEvent>.multi((sink) {
      if (_disposed || rideId != reservationId) {
        sink.close();
        return;
      }

      void emitCurrent() {
        final event = _eventForCurrent();
        if (event != null) sink.add(event);
      }

      controller.addListener(emitCurrent);
      scheduleMicrotask(emitCurrent);
      sink.onCancel = () {
        controller.removeListener(emitCurrent);
      };
    });
  }

  @override
  Future<void> reconnectAndResync(String rideId) async {
    if (_disposed || rideId != reservationId) return;
    await controller.hydrate();
  }

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {
    // Reservation transport has no authoritative rider->driver signal channel
    // yet. The UI disables that action instead of pretending it was sent.
  }

  @override
  void unsubscribe() {
    // Stream cancellation removes the ReservationController listener.
  }

  @override
  void cancelRide() {
    if (_disposed) return;
    final ride = controller.byId(reservationId);
    if (ride == null || !ride.status.canCancel) return;
    // rider-65: the reservation's own late-cancel terms, as the live
    // screen's sheet and the Upcoming page apply them.
    unawaited(
      controller.cancel(
        reservationId,
        reason: 'rider_cancelled_live',
        fee: controller.cancelTermsFor(ride).fee,
      ),
    );
  }

  @override
  void researchAfterDriverCancel() {
    if (_disposed) return;
    final ride = controller.byId(reservationId);
    if (ride == null) return;
    if (ride.status == ReservationStatus.driverAssignmentPending) return;
    if (!ride.status.hasDriver) return;
    unawaited(controller.driverCancelled(reservationId));
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
