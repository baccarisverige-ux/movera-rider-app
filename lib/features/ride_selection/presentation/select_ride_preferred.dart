part of 'select_ride.dart';

/// Saved-places design (owner 2026-11-18, Rules
/// decisions/session-2026-11-18-saved-places-design.md steps 3b-7).
extension _SelectRidePreferred on _SelectRideState {
  /// Step 5-7: the saved place's fixed category. When this zone offers it
  /// now (now or Senare alike) and it has a bookable price, it is chosen
  /// and Set pickup opens at once with a "Byt kategori" link back here.
  /// When it is not offered, this screen stays with only the categories
  /// that are (the saved choice is kept for next time). Once per screen.
  void _openPreferredOnce() {
    final id = widget.preferredCategoryId;
    if (id == null || _preferredTried || !mounted) return;
    _preferredTried = true;
    final ride = _selection.rideByIdOrNull(id);
    if (ride == null || !_selection.quoteIsAvailable(id)) {
      _showCategories();
      if (ride != null) {
        MoveraToast.show(
          context,
          context.l10n.placesCategoryNotHere(ride.name),
        );
      }
      return;
    }
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selection.selectRide(
        ride.id,
        ride.price,
        catalogCurrency: ride.currency,
      );
    });
    _preferredOpened = true;
    _book();
    // Nothing opened (no price, no payment...): the categories, as usual.
    if (!_bookingInFlight) _showCategories();
  }

  void _showCategories() {
    if (!_preferredHidden || !mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _preferredHidden = false);
  }

  /// Step 5 "skip": while a fixed category is being opened the categories
  /// are never drawn; this plain screen (prices loading) is all there is
  /// under Set pickup. "Byt kategori" (Set pickup's back) shows them.
  Widget _preferredHolding() => const Scaffold(
    key: ValueKey('select-ride-preferred-holding'),
    backgroundColor: Colors.white,
    body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
  );

  /// Step 3b / 4 / 4b: the S3 save sheet over the screen.
  Widget _saveSheetLayer() => Positioned.fill(
    child: PlaceSaveSheet(
      address: widget.offerSaveAddress!,
      categories: () => [
        for (final ride in _selection.rides())
          if (_selection.quoteIsAvailable(ride.id))
            (id: ride.id, name: rideNameFor(ride.name)),
      ],
    ),
  );
}
