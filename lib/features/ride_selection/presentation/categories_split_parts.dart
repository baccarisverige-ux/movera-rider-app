import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

// The categories screen's two-part open (owner 2026-11-18, saved-places
// design step 9), split out of select_ride.dart (Rule 25: under 1,500 lines).

/// Owner 2026-11-18: the back + route header slides down from above the
/// screen while the categories route opens (and back up on Back).
Widget categoriesSplitHeader(
  CategoriesSplit? split,
  MediaQueryData media,
  Widget header, {
  required double barHeight,
}) {
  if (split == null) return header;
  // Its bottom, with its shadow, sits this far below the top edge.
  final headerBottom = media.padding.top + 8 + barHeight + 24;
  return AnimatedBuilder(
    animation: split.animation,
    builder: (context, child) => Transform.translate(
      key: const ValueKey('categories-split-header'),
      offset: Offset(0, split.headerShift(headerBottom)),
      child: child,
    ),
    child: header,
  );
}

/// Owner 2026-11-18: the car sheet (and its payment + Book footer) rises
/// from below the screen to meet the header; Back sends it down again.
Widget categoriesSplitSheet(
  CategoriesSplit? split,
  MediaQueryData media,
  Key key,
  Widget sheet,
) {
  if (split == null) return sheet;
  return AnimatedBuilder(
    animation: split.animation,
    builder: (context, child) => Transform.translate(
      key: key,
      offset: Offset(0, split.sheetShift(media.size.height)),
      child: child,
    ),
    child: sheet,
  );
}
