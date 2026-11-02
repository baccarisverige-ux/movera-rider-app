import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';

// ignore: must_be_immutable
class TextWidget extends StatelessWidget {
  String? text;
  double? fontSize;
  Color? color;
  TextAlign? textAlign;
  double? letterSpacing;
  Paint? foreground;
  FontWeight fontWeight;
  bool isItalic;
  int? maxLines;
  TextOverflow? overflow;

  TextWidget({
    super.key,
    this.text,
    this.fontSize,
    this.color = AppColor.title,
    this.textAlign,
    this.letterSpacing,
    this.foreground,
    this.fontWeight = FontWeight.w500,
    this.isItalic = false,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      textAlign: textAlign,
      text!,
      maxLines: maxLines,
      overflow: overflow,
      style: GoogleFonts.poppins(
        foreground: foreground,
        letterSpacing: letterSpacing,
        fontSize: ResSize.setSp(fontSize!),
        fontWeight: fontWeight,
        color: color,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}
