import 'package:flutter/material.dart';

/// Owner round 4: the Home sheet sits square on the map, with no rounded
/// corners, and is raised over it by an upward shadow: the same edge the
/// sign-in card has over its scene ("make it look like 3D").
abstract final class HomeSheetEdge {
  /// A wide soft shadow cast upward plus a tight one at the edge.
  static const List<BoxShadow> shadows = [
    BoxShadow(color: Color(0x26000000), blurRadius: 36, offset: Offset(0, -14)),
    BoxShadow(color: Color(0x12000000), blurRadius: 6, offset: Offset(0, -2)),
  ];

  /// The sheet's surface: white, square, raised.
  static const BoxDecoration decoration = BoxDecoration(
    color: Colors.white,
    boxShadow: shadows,
  );
}
