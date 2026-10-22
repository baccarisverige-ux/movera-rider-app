import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The side gutter, read at its use so it follows a window resize (and is
/// never fixed from ScreenUtil's defaults before ScreenUtilInit ran,
/// rider-96).
double get screenHorizPadding => ScreenUtil().setWidth(16);

class ResSize {
  static double get h => ScreenUtil().scaleHeight;
  static double get w => ScreenUtil().scaleWidth;
  static double setWidth(double size) => ScreenUtil().setWidth(size);
  static double setHeight(double size) => ScreenUtil().setHeight(size);

  static double setSp(double fontSize) => ScreenUtil().setSp(fontSize);
}
