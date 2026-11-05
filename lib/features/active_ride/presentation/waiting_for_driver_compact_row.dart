part of 'waiting_for_driver.dart';

extension _WaitingCompactRow on _WaitingForDriverState {
  /// The low stop: one clean row with the ETA, the driver and the plate.
  /// Tapping it brings the sheet back to the middle.
  Widget _compactRow(
    MediaQueryData media,
    MatchedDriver? driver,
    String headline,
  ) {
    final plate = driver?.plate?.trim() ?? '';
    return Positioned(
      top: _WaitingForDriverState._handleHeight,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _sheetController,
        builder: (context, child) {
          final open = _openness(media);
          final t = Curves.easeOutCubic.transform(
            (1 - open / 0.6).clamp(0.0, 1.0),
          );
          // Out of the tree while hidden, so it never doubles the header.
          if (t <= 0.01) return const SizedBox.shrink();
          return IgnorePointer(
            ignoring: t < 0.5,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - t)),
                child: child,
              ),
            ),
          );
        },
        child: InkWell(
          key: const ValueKey<String>('waiting-compact-row'),
          onTap: () {
            HapticFeedback.selectionClick();
            _sheetController.animateTo(
              SheetOffset.absolute(_minSheet(media)),
              duration: MoveraDurations.normal,
              curve: Curves.easeOutCubic,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                DriverPhotoAvatar(
                  driver: driver,
                  radius: 22,
                  fallback: Text(
                    driver?.initial ?? '',
                    style: waitingText(15, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: waitingText(17, weight: FontWeight.w700),
                      ),
                      if (driver != null)
                        Text(
                          [
                            driver.displayFirstName,
                            if (driver.vehicleLabel.isNotEmpty)
                              driver.vehicleLabel,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: waitingText(
                            13,
                            color: const Color(0xFF5C656C),
                          ),
                        ),
                    ],
                  ),
                ),
                if (plate.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E7EB)),
                    ),
                    child: Text(
                      plate,
                      style: waitingText(14, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
