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
                  capture.onChanged = (value) {
                    AppScope.instance.destinationSearch.type(value, (text) {
                      // RIDE-20: the sheet's own context, not Home's — the
                      // debounce can fire after the sheet has closed.
                      if (!context.mounted) return;
                      setModalState(() => query = text);
                    });
                  };
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
                  // rider-u123: MoveraSheet already lifts the sheet over the
                  // keyboard; padding by the inset again here doubled it.
                  return Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.78,
                    ),
                    padding: EdgeInsets.fromLTRB(
                      ResSize.w * 18,
                      ResSize.h * 11,
                      ResSize.w * 18,
                      ResSize.h * 20,
                    ),
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
                          width: ResSize.w * 42,
                          height: ResSize.h * 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCED4D8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        16.height,
                        Row(
                          children: [
                            Expanded(
                              child: TextWidget(
                                text: _targetTitle(target, customType),
                                color: _HomeState._premiumInk,
                                fontSize: 18,
                                fontWeight: fwBold,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                              color: _HomeState._premiumInk,
                              tooltip: context.l10n.close,
                            ),
                          ],
                        ),
                        10.height,
                        TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            AppScope.instance.destinationSearch.type(value, (
                              text,
                            ) {
                              if (!context.mounted) return;
                              setModalState(() => query = text);
                            });
                          },
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              Navigator.pop(sheetContext, value.trim());
                            }
                          },
                          style: TextStyle(
                            color: _HomeState._premiumInk,
                            fontSize: ResSize.setSp(15),
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: context.l10n.searchOrEnterAddress,
                            hintStyle: TextStyle(
                              color: _HomeState._premiumMuted.withValues(
                                alpha: 0.72,
                              ),
                              fontSize: ResSize.setSp(14),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: _HomeState._premiumInk.withValues(
                                alpha: 0.72,
                              ),
                            ),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      controller.clear();
                                      setModalState(() => query = '');
                                    },
                                    tooltip: context.l10n.clear,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            filled: true,
                            fillColor: const Color(0xFFF5F7F7),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: ResSize.w * 15,
                              vertical: ResSize.h * 15,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        12.height,
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            // Save the real street address, never the
                            // words "Current location".
                            onTap: _currentAddressToSave() == null
                                ? null
                                : () => Navigator.pop(
                                    sheetContext,
                                    _currentAddressToSave(),
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResSize.w * 13,
                                vertical: ResSize.h * 11,
                              ),
                              decoration: BoxDecoration(
                                color: _HomeState._premiumAccentSoft.withValues(
                                  alpha: 0.62,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    color: _HomeState._premiumAccent,
                                    size: ResSize.h * 20,
                                  ),
                                  11.width,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TextWidget(
                                          text: context.l10n.useCurrentLocation,
                                          color: _HomeState._premiumInk,
                                          fontSize: 12.5,
                                          fontWeight: fwSemiBold,
                                        ),
                                        2.height,
                                        TextWidget(
                                          text:
                                              _placeOrNull(_pickupAddress) ==
                                                  null
                                              ? context.l10n.findingYourAddress
                                              : _shortAddress(
                                                  _pickupAddress,
                                                  maxLength: 38,
                                                ),
                                          color: _HomeState._premiumMuted,
                                          fontSize: 9,
                                          fontWeight: fwNormal,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (filteredRecent.isNotEmpty) ...[
                          16.height,
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextWidget(
                              text: context.l10n.recentAddresses,
                              color: _HomeState._premiumMuted,
                              fontSize: 10.5,
                              fontWeight: fwSemiBold,
                            ),
                          ),
                          6.height,
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              itemCount: filteredRecent.length,
                              separatorBuilder: (_, __) => const Divider(
                                color: Color(0xFFE7EBEE),
                                height: 1,
                              ),
                              itemBuilder: (context, index) {
                                final address = filteredRecent[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: ResSize.w * 4,
                                  ),
                                  leading: Icon(
                                    Icons.history_rounded,
                                    color: _HomeState._premiumMuted,
                                    size: ResSize.h * 20,
                                  ),
                                  title: TextWidget(
                                    text: address,
                                    color: _HomeState._premiumInk,
                                    fontSize: 11,
                                    fontWeight: fwMedium,
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, address),
                                );
                              },
                            ),
                          ),
                        ],
                        if (query.trim().isNotEmpty) ...[
                          14.height,
                          Material(
                            color: _HomeState._premiumAccent,
                            borderRadius: BorderRadius.circular(17),
                            child: InkWell(
                              onTap: () => Navigator.pop(
                                sheetContext,
                                controller.text.trim(),
                              ),
                              borderRadius: BorderRadius.circular(17),
                              child: SizedBox(
                                height: ResSize.h * 46,
                                width: double.infinity,
                                child: Center(
                                  child: TextWidget(
                                    text: context.l10n.useThisAddress,
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: fwSemiBold,
                                  ),
                                ),
                              ),
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
