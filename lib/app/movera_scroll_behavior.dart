import 'package:flutter/material.dart';

/// Owner 2026-11-24 (iPhone): no screen may bounce past its edge. iOS scroll
/// views bounce by default, which pulled content away from the screen top and
/// opened an empty band under the bottom navigation. Every scroll view in the
/// app clamps at its edges on every platform.
class MoveraScrollBehavior extends MaterialScrollBehavior {
  const MoveraScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
