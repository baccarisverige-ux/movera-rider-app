import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/platform/safe_area_insets.dart';
import 'package:web/web.dart' as web;

/// Reads `env(safe-area-inset-*)` from a hidden, fixed probe element whose
/// padding is those four values. Without `viewport-fit=cover` (removed from
/// web/index.html on 2026-10-31) they are all 0.
SafeAreaSource platformSafeAreaSource() => _CssSafeArea();

class _CssSafeArea implements SafeAreaSource {
  _CssSafeArea() {
    final probe = web.document.createElement('div') as web.HTMLDivElement;
    probe.id = 'movera-safe-area-probe';
    probe.setAttribute('aria-hidden', 'true');
    probe.style
      ..position = 'fixed'
      ..top = '0'
      ..left = '0'
      ..width = '0'
      ..height = '0'
      ..visibility = 'hidden'
      ..pointerEvents = 'none'
      ..setProperty(
        'padding',
        'env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) '
            'env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px)',
      );
    web.document.documentElement?.append(probe);
    _probe = probe;
  }

  late final web.HTMLDivElement _probe;
  final List<StreamSubscription<web.Event>> _subscriptions = [];

  static double _px(String value) =>
      double.tryParse(value.replaceAll('px', '').trim()) ?? 0;

  @override
  EdgeInsets read() {
    final style = web.window.getComputedStyle(_probe);
    return EdgeInsets.fromLTRB(
      _px(style.paddingLeft),
      _px(style.paddingTop),
      _px(style.paddingRight),
      _px(style.paddingBottom),
    );
  }

  @override
  void listen(VoidCallback onChange) {
    void later(web.Event _) {
      onChange();
      // iOS settles the insets a moment after a rotation.
      Timer(const Duration(milliseconds: 300), onChange);
    }

    _subscriptions
      ..add(
        web.EventStreamProvider<web.Event>(
          'resize',
        ).forTarget(web.window).listen(later),
      )
      ..add(
        web.EventStreamProvider<web.Event>(
          'orientationchange',
        ).forTarget(web.window).listen(later),
      );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _probe.remove();
  }
}
