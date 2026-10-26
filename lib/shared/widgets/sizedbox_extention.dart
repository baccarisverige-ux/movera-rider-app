import 'package:flutter/material.dart';

import 'responsive_size.dart';

extension SizedBoxExtension on num {
  SizedBox get height => SizedBox(height: ResSize.h * this);

  SizedBox get width => SizedBox(width: ResSize.w * this);
}
