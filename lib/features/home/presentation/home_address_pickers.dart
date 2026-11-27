part of 'home.dart';

extension _HomeAddressPickers on _HomeState {
  Future<void> _showAddressPicker({
    required String target,
    String? customType,
    String? placeId,
  }) async {
    final initialAddress = _existingAddressFor(target);
    final controller = TextEditingController(
      text: initialAddress == 'Current location' ? '' : initialAddress ?? '',
    );
    final focusNode = FocusNode();
    var query = controller.text;
    // Started before the sheet opens; see EarlyInputCapture.
    final capture = EarlyInputCapture()..start();
    capture.attach(controller, focusNode);
    // Saved places v4 (owner 2026-11-27): the real suggestions while
    // typing, through the shared AddressSuggestionList, not only recents.
    final suggester = AddressSuggester();
    String? selected;
    try {
      selected = await MoveraSheet.show<String>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.24),
        builder: (sheetContext) {
          return MoveraSheetDisposables(
            disposables: [controller, focusNode],
            child: PointerInterceptor(
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  void typed(String value) {
                    suggester.type(value);
                    AppScope.instance.destinationSearch.type(value, (text) {
                      // RIDE-20: the sheet's own context, not Home's — the
                      // debounce can fire after the sheet has closed.
                      if (!context.mounted) return;
                      setModalState(() => query = text);
                    });
                  }

                  capture.onChanged = typed;
                  final filteredRecent = _recentAddresses
                      .where(
                        (address) =>
                            query.trim().isEmpty ||
                            address.toLowerCase().contains(
                              query.trim().toLowerCase(),
                            ),
                      )
                      .take(6)
                      .toList();
                  final current = _currentAddressToSave();
                  // rider-u123: MoveraSheet already lifts the sheet over the
                  // keyboard; padding by the inset again here doubled it.
                  return Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.78,
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 11, 24, 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: SpStyle.chipBorder,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        12.height,
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _targetTitle(target, customType),
                                style: SpStyle.text(
                                  size: 22,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                              color: SpStyle.ink,
                              tooltip: context.l10n.close,
                            ),
                          ],
                        ),
                        8.height,
                        TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: typed,
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              Navigator.pop(sheetContext, value.trim());
                            }
                          },
                          style: SpStyle.text(),
                          cursorColor: SpStyle.ink,
                          decoration: SpStyle.underline(
                            hint: context.l10n.searchOrEnterAddress,
                            prefix: const Icon(
                              Icons.search,
                              color: SpStyle.ink,
                              size: 20,
                            ),
                            suffix: query.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      controller.clear();
                                      suggester.type('');
                                      setModalState(() => query = '');
                                    },
                                    tooltip: context.l10n.clear,
                                    icon: const Icon(
                                      Icons.close,
                                      color: SpStyle.ink,
                                      size: 20,
                                    ),
                                  ),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Save the real street address, never the
                                // words "Current location".
                                AddressSuggestionList(
                                  suggester: suggester,
                                  style: AddressSuggestionStyle.plain,
                                  currentLocationLabel:
                                      context.l10n.useCurrentLocation,
                                  currentLocationDetail:
                                      _placeOrNull(_pickupAddress) == null
                                      ? context.l10n.findingYourAddress
                                      : _shortAddress(
                                          _pickupAddress,
                                          maxLength: 38,
                                        ),
                                  onUseCurrentLocation: current == null
                                      ? () {}
                                      : () => Navigator.pop(
                                          sheetContext,
                                          current,
                                        ),
                                  onPick: (s) =>
                                      Navigator.pop(sheetContext, s.address),
                                  empty: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final address in filteredRecent)
                                        SpStyle.row(
                                          icon: Icons.history,
                                          name: address,
                                          onTap: () => Navigator.pop(
                                            sheetContext,
                                            address,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (query.trim().isNotEmpty) ...[
                          14.height,
                          SpStyle.pill(
                            label: context.l10n.useThisAddress,
                            onPressed: () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    } finally {
      capture.stop();
      suggester.dispose();
    }
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    await _saveAddressFor(
      target,
      selected,
      customType: customType,
      placeId: placeId,
    );
  }

  String _placeLabel(String type) {
    switch (type) {
      case 'gym':
        return context.l10n.placeGym;
      case 'mall':
        return context.l10n.placeMall;
      case 'school':
        return context.l10n.placeSchool;
      case 'airport':
        return context.l10n.placeAirport;
      case 'family':
        return context.l10n.placeFamily;
      case 'restaurant':
        return context.l10n.placeRestaurant;
      default:
        return context.l10n.placeOther;
    }
  }

  IconData _placeIcon(String type) {
    switch (type) {
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'mall':
        return Icons.local_mall_outlined;
      case 'school':
        return Icons.school_outlined;
      case 'airport':
        return Icons.flight_takeoff_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      default:
        return Icons.place_outlined;
    }
  }
}
