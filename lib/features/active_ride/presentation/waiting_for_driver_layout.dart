// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingLayout on _WaitingForDriverState {
  void _syncSheetOverlay() {
    if (!_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;
    final offset = _sheetController.metrics?.offset;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 140), _onSheetSettled);
    final cover = offset != null && offset > _minSheet(media) + 12;
    if (cover == _overlayOn) return;
    _overlayOn = cover;
    setWebOverlayOpen(cover);
  }

  /// G26-back: Android back before pickup. A sheet raised above its
  /// resting stop goes back down to it; otherwise nothing happens (the
  /// screen stays, and cancelling is the close button's job).
  void _lowerSheetOnBack() {
    if (!_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    final offset = _sheetController.metrics?.offset;
    if (media == null || offset == null) return;
    final rest = _minSheet(media);
    if (offset <= rest + 1.5) return;
    _sheetController.animateTo(
      SheetOffset.absolute(rest),
      duration: MoveraDurations.normal,
      curve: Curves.easeOutCubic,
    );
  }

  /// A light haptic when the sheet lands on a stop; the map then reframes
  /// gently so the driver and the pickup stay above the sheet.
  void _onSheetSettled() {
    if (!mounted || !_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    final offset = _sheetController.metrics?.offset;
    if (media == null || offset == null) return;
    for (final snap in _snaps(media)) {
      if ((offset - snap).abs() > 1.5) continue;
      final last = _settledSheet;
      if (last != null && (last - snap).abs() < 1.5) return;
      if (last != null) HapticFeedback.selectionClick();
      setState(() => _settledSheet = snap);
      return;
    }
  }

  Future<void> _parkMapForStageChange() async {
    if (_mapParked) return;
    _mapParked = true;
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.waiting);
    // G25: a map kept mounted under the next screen (native) stops its
    // camera and marker work until it is shown again.
    _mapKey.currentState?.pauseWhileParked();
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
  }

  void _recenterMap() {
    final eta = _tracking.eta;
    final target = _isInTrip
        ? (eta?.latitude != null && eta?.longitude != null
              ? GeoPoint(eta!.latitude!, eta.longitude!)
              : GeoPoint(
                  _destinationPosition.latitude,
                  _destinationPosition.longitude,
                ))
        : GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude);
    AppScope.instance.camera.focusOnPickup(target);
  }
}
