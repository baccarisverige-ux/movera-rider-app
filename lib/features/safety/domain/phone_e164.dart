class SwedishPhone {
  static final _digits = RegExp(r'^\d+$');

  static String? toE164(String raw) {
    var value = raw.replaceAll(RegExp(r'[\s\-().]'), '');
    if (value.isEmpty) return null;
    if (value.startsWith('0046')) {
      value = '+46${value.substring(4)}';
    } else if (value.startsWith('0') && !value.startsWith('00')) {
      value = '+46${value.substring(1)}';
    } else if (value.startsWith('46') && !value.startsWith('+')) {
      value = '+$value';
    }
    if (!value.startsWith('+46')) return null;
    var rest = value.substring(3);
    // rider-83: "+46 070 ..." keeps the domestic trunk zero; it is not part
    // of the E.164 number, and the national number never starts with 0.
    if (rest.startsWith('0')) rest = rest.substring(1);
    if (rest.length < 7 || rest.length > 10) return null;
    if (!_digits.hasMatch(rest) || rest.startsWith('0')) return null;
    return '+46$rest';
  }

  static String display(String e164) {
    if (!e164.startsWith('+46') || e164.length < 6) return e164;
    final rest = e164.substring(3);
    if (rest.startsWith('7') && rest.length >= 9) {
      return '+46 ${rest.substring(0, 2)} ${rest.substring(2, 5)} ${rest.substring(5, 7)} ${rest.substring(7)}';
    }
    return '+46 $rest';
  }
}
