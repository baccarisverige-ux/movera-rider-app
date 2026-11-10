// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingResearch on _WaitingForDriverState {
  Future<void> _researchAfterDriverCancel() async {
    if (_researching) return;
    _researching = true;
    final lostDriver = _tracking.driver ?? widget.driver;
    final byAdmin = _tracking.reassignedByAdmin;
    _tracking.dispose();

    // The rider is not asked anything: their ride is still on, so the search
    // starts again straight away and a short notice says why the driver
    // changed.
    if (!mounted) {
      _researching = false;
      return;
    }
    // Q13: an admin reassign is not the driver's doing; the rider just sees
    // the search, then the next driver assigned.
    if (!byAdmin) {
      showDriverCancelledNotice(context, driverName: lostDriver?.firstName);
    }

    await _parkMapForStageChange();
    if (!mounted) {
      _researching = false;
      return;
    }

    final customDriverCancelled = widget.onDriverCancelled;
    if (customDriverCancelled != null) {
      _leaving = true;
      setState(() {});
      try {
        await customDriverCancelled(context);
      } finally {
        _researching = false;
      }
      return;
    }

    // Same ride, same price, same addresses — only the driver changes.
    // Re-open the shared session before restarting dispatch. The tracking
    // controller already reconciled the driver-drop event as terminal, and
    // without this explicit reversible dispatch transition the parked Finding
    // route observes a stale cancelledByDriver session once the search restarts.
    final redispatchRideId = _rideId;
    await _ride.resumeSearchingAfterDriverCancel(rideId: redispatchRideId);
    if (!mounted) {
      _researching = false;
      return;
    }
    _realtime.researchAfterDriverCancel();
    _leaving = true;
    setState(() {});

    final navigator = Navigator.of(context);
    // Close what Waiting opened on top of itself (driver profile, chat, a
    // sheet) first, so the pop below leaves Waiting and not that page.
    final own = ModalRoute.of(context);
    if (own != null && own.isActive && !own.isCurrent) {
      navigator.popUntil((route) => route == own);
    }
    if (navigator.canPop()) {
      // Normal forward path already has the parked Finding route directly
      // underneath this screen. Return to it instead of stacking another
      // Finding route every time a driver drops the ride.
      _researching = false;
      navigator.pop(true);
      return;
    }

    // Cold restore can put Waiting directly inside RideRestoreGate, with no
    // pushed Finding route underneath. Replace only the gate child so the app
    // root/navigator stays intact.
    final finding = FindingDrivers(
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      pickupPosition: _pickupPosition,
      destinationPosition: _destinationPosition,
      rideType: widget.rideType,
      price: _price,
      currency: widget.currency,
      paymentMethod: widget.paymentMethod,
      walletAmountMinor: widget.walletAmountMinor,
      notes: widget.notes,
      stops: _stops,
    );
    final coordinator = RideRestoreCoordinator.instance;
    if (coordinator.replaceRootSurface(finding, RestoredSurface.finding)) {
      _researching = false;
      return;
    }

    // Widget tests or isolated hosts may not have RideRestoreGate installed.
    _researching = false;
    Navigator.pushReplacement(
      context,
      RideStageTransition(
        finding,
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
  }
}
