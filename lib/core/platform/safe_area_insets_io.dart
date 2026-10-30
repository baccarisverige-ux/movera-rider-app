import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/platform/safe_area_insets.dart';

/// Store apps: the system's insets are in [MediaQuery] already.
SafeAreaSource platformSafeAreaSource() => _None();

class _None implements SafeAreaSource {
  @override
  EdgeInsets read() => EdgeInsets.zero;

  @override
  void listen(VoidCallback onChange) {}

  @override
  void dispose() {}
}
