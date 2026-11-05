part of 'home.dart';

extension _HomeCollapsedSheet on _HomeState {
  Widget _premiumCollapsedSheet(
    double sheetProgress,
    double detailProgress,
    double sheetHeight, {
    required Widget toggleHandle,
    required Widget whereToCard,
    required Widget Function(double reveal) savedPlacesContent,
    required Widget detailContent,
  }) {
    final promotion = _promotion;
    // Content keeps its full size and slides/fades in instead of being cut.
    final placesReveal = Curves.easeOutCubic.transform(
      ((sheetProgress - 0.25) / 0.75).clamp(0.0, 1.0),
    );
    final detailReveal = Curves.easeOutCubic.transform(
      ((detailProgress - 0.15) / 0.85).clamp(0.0, 1.0),
    );
    final ticketVisible = 1 - Curves.easeOutCubic.transform(detailProgress);
    // UI-4: the toggle handle's target is 12 px taller than the 32 px it
    // used to be; half comes out of the padding above, half out of the gap.
    final handleLift = math.min(6.0, ResSize.h * 11);
    // Owner round 4: square corners, raised over the map by an upward
    // shadow (HomeSheetEdge), like the sign-in card over its scene.
    return Container(
      key: const ValueKey('home-sheet-surface'),
      decoration: HomeSheetEdge.decoration,
      child: HorizontalSwipe(
        onSwipeLeft: _openPayment,
        child: SafeArea(
          top: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              HomeSheetScroll(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    HomeSheetLayout.sideMargin,
                    ResSize.h * 11 - handleLift,
                    HomeSheetLayout.sideMargin,
                    ResSize.h * 7,
                  ),
                  child: Column(
                    children: [
                      toggleHandle,
                      SizedBox(
                        height: math.max(0.0, ResSize.h * 12 + handleLift - 12),
                      ),
                      if (promotion != null)
                        IgnorePointer(
                          ignoring: ticketVisible < 0.6,
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: ticketVisible,
                            child: Opacity(
                              opacity: ticketVisible,
                              child: Transform.translate(
                                offset: Offset(0, -10 * (1 - ticketVisible)),
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: ResSize.h * 10,
                                  ),
                                  // Owner round 1: the "simple row" here;
                                  // the ride list keeps the ticket.
                                  child: PromotionTicket(
                                    promotion: promotion,
                                    flat: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      whereToCard,
                      IgnorePointer(
                        ignoring: sheetProgress < 0.92,
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: sheetProgress,
                          child: savedPlacesContent(placesReveal),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: detailProgress < 0.92,
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: detailProgress,
                          child: Opacity(
                            opacity: detailReveal,
                            child: Transform.translate(
                              offset: Offset(0, 12 * (1 - detailReveal)),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: HomeSheetLayout.sectionGap,
                                ),
                                child: detailContent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: ResSize.w * (18 + (12 * (1 - sheetProgress))),
                right: ResSize.w * (18 + (12 * (1 - sheetProgress))),
                // Owner 2026-11-02 ("Yes, move it up"): with the sheet open
                // the docked bar sits just above the bottom safe area (home
                // indicator), so the tabs are fully tappable. Unchanged with
                // the sheet down.
                top:
                    sheetHeight -
                    ResSize.h * (63 + (30 * (1 - sheetProgress))) -
                    MediaQuery.paddingOf(context).bottom * sheetProgress,
                child: Transform.scale(
                  scale: 0.84 + (0.16 * sheetProgress),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    // UI-4: the vertical padding is passed to the items as
                    // hitSlop, so the targets reach the bar's edges.
                    padding: EdgeInsets.symmetric(
                      horizontal: ResSize.w * (4 * (1 - sheetProgress)),
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.white,
                      borderRadius: BorderRadius.circular(
                        32 * (1 - sheetProgress),
                      ),
                      border: Border.all(
                        color: _HomeState._premiumLine.withValues(
                          alpha: 1 - sheetProgress,
                        ),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.14 * (1 - sheetProgress),
                          ),
                          blurRadius: 28 * (1 - sheetProgress),
                          offset: Offset(0, 10 * (1 - sheetProgress)),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: sheetProgress,
                          child: const Divider(
                            color: Color(0xFFE7EBEE),
                            thickness: 0.8,
                            height: 1,
                          ),
                        ),
                        SizedBox(height: ResSize.h * (9 * sheetProgress)),
                        LiquidGlassNavRow(
                          selectedIndex: HomeTabs.home,
                          floatingFraction: 1 - sheetProgress,
                          hitSlop: ResSize.h * (5 * (1 - sheetProgress)),
                          itemHeight: ResSize.h * 52,
                          entries: [
                            LiquidGlassNavEntry(
                              iconAsset: AppAssets.solarHome,
                              label: context.l10n.navHome,
                              onTap: () => _animateHomeSheetTo(
                                SheetOffset.absolute(_sheetMinPixels),
                              ),
                            ),
                            LiquidGlassNavEntry(
                              iconAsset: AppAssets.solarWallet,
                              label: context.l10n.navPayment,
                              onTap: _openPayment,
                            ),
                            LiquidGlassNavEntry(
                              iconAsset: AppAssets.solarCalendar,
                              label: context.l10n.navScheduleRide,
                              onTap: () => unawaited(_openSchedule()),
                            ),
                            LiquidGlassNavEntry(
                              iconAsset: AppAssets.solarUser,
                              label: context.l10n.navAccount,
                              onTap: _openAccount,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
