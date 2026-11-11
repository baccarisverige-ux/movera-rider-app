import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';

Widget customTextfield({
  TextEditingController? controller,
  VoidCallback? ontap,
  String? hint,
  bool? isobscure = false,
  Widget? prefixWidget,
  Widget? suffixWidget,
  Function? onFieldSubmitted,
  Function? onChanged,
  bool onChangedbool = false,
  // double contentVerticlePadding = 19,
  String? Function(String?)? onValidator,
  // bool validator = false,
  TextInputType? keyboardType,
  int maxline = 1,
  Color fillColor = Colors.transparent,
  double borderWidth = 0.5,
  Color borderColor = AppColor.border,
  double borderRadius = 8,
  Color hintTextColor = AppColor.hintText,
  Color textColor = AppColor.title,
  double contentVertPadding = 16,
  double contentHorizPadding = 16,
  bool enabled = true,
  double fontSize = 16,
  FocusNode? focusNode,
  bool readOnly = false,
  TextInputAction? textInputAction,
  List<TextInputFormatter>? inputFormatters,
}) {
  return TextFormField(
    focusNode: focusNode,
    readOnly: readOnly,
    onTap: ontap,
    enabled: enabled,
    validator: onValidator,
    textInputAction: textInputAction,
    inputFormatters: inputFormatters,
    onChanged: (v) {
      onChangedbool ? onChanged!(v) : (v) {};
    },
    maxLines: maxline,
    keyboardType: keyboardType,
    onFieldSubmitted: (value) {
      if (onFieldSubmitted != null) {
        onFieldSubmitted(value);
      }
    },

    style: GoogleFonts.poppins(
      color: textColor,
      fontSize: ResSize.setSp(fontSize),
      fontWeight: fwMedium,
    ),
    controller: controller,
    textAlign: TextAlign.start,
    obscureText: isobscure!,
    decoration: InputDecoration(
      contentPadding: EdgeInsets.symmetric(
        horizontal: ResSize.w * contentHorizPadding,
        vertical: ResSize.h * contentVertPadding,
      ),
      hintStyle: GoogleFonts.poppins(
        color: hintTextColor,
        fontSize: ResSize.setSp(fontSize),
        fontWeight: fwMedium,
      ),
      hintText: hint,
      fillColor: fillColor,
      filled: true,
      prefixIcon: prefixWidget,
      suffixIcon: suffixWidget,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: Colors.transparent, width: 0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: Colors.transparent, width: 0),
      ),
      errorStyle: GoogleFonts.poppins(
        color: Colors.red,
        fontSize: ResSize.setSp(fontSize),
        fontWeight: fwMedium,
      ),
    ),
  );
}
