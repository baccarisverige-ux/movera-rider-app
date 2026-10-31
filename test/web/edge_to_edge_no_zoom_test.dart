import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/platform/safe_area_insets.dart';

class _Fixed implements SafeAreaSource {
  _Fixed(this.insets);
  EdgeInsets insets;
  VoidCallback? onChange;

  @override
  EdgeInsets read() => insets;

  @override
  void listen(VoidCallback onChange) => this.onChange = onChange;

  @override
  void dispose() {}
}

/// Owner 2026-10-30 "Map under the strip" and the iPhone 15 / iOS 17 zoom
/// check (same Flutter web setup as the driver app).
void main() {
  final html = File('web/index.html').readAsStringSync();

  test('the page is edge to edge, fixed at 0,0 (one origin for drawing and '
      'taps), and viewport-fit=cover survives the engine\'s viewport swap', () {
    expect(html, contains('viewport-fit=cover'));
    expect(html, contains("new MutationObserver(cover).observe(document.head"));
    expect(
      html,
      contains(
        'apple-mobile-web-app-status-bar-style" content="black-translucent"',
      ),
    );
    expect(
      RegExp(
        r'html, body \{[^}]*position: fixed;[^}]*inset: 0;',
        dotAll: true,
      ).hasMatch(html),
      isTrue,
    );
  });

  test('Safari never zooms on a field: inputs are 16px', () {
    expect(
      html,
      contains('input, textarea, select { font-size: 16px !important; }'),
    );
  });

  testWidgets('the page\'s safe-area insets reach MediaQuery; the keyboard '
      'keeps the bottom', (tester) async {
    final source = _Fixed(const EdgeInsets.only(top: 59, bottom: 34));
    late MediaQueryData seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: SafeAreaFromPage(
          source: source,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen.padding.top, 59);
    expect(seen.viewPadding.bottom, 34);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: 336),
        ),
        child: SafeAreaFromPage(
          source: source,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen.padding.top, 59);
    expect(seen.padding.bottom, 0);

    // Rotation: new insets are read again.
    source.insets = const EdgeInsets.only(left: 47, right: 47, bottom: 21);
    source.onChange!();
    await tester.pump();
    expect(seen.padding.left, 47);
  });
}
