import 'package:movera_rider/shared/widgets/responsive_size.dart';

/// Owner round 1 ("make everything even"): one vertical gap between the
/// sections of the expanded Home sheet, one corner radius for its cards and
/// one side margin for its content. Design pixels go through [ResSize].
abstract final class HomeSheetLayout {
  /// The gap between two sections of the expanded sheet, in design px.
  static const double sectionGapDesign = 14;

  /// The corner radius of every card on the expanded sheet.
  static const double cardRadius = 20;

  /// The sheet content's side margin, in design px.
  static const double sideMarginDesign = 18;

  static double get sectionGap => ResSize.h * sectionGapDesign;

  static double get sideMargin => ResSize.w * sideMarginDesign;
}
