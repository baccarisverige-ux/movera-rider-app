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

/// Owner 2026-10-31 "Go back to before": the edge-to-edge page (Map under
/// the strip, rider #448/#449) left the iPhone Home Screen app short of the
/// bottom, so web/index.html is back to the layout before it; the iPhone 15 /
/// iOS 17 no-zoom rule stays (same Flutter web setup as the driver app).
void main() {
  final html = File('web/index.html').readAsStringSync();

  test('the page layout is the one before edge to edge: no viewport-fit, '
      'no fixed page, no viewport-gap script', () {
    expect(html, isNot(contains('viewport-fit')));
    expect(html, isNot(contains('MutationObserver(cover)')));
    expect(html, isNot(contains('movera-viewport-gap')));
    expect(html, isNot(contains('position: fixed')));
    expect(
      html,
      contains(
        '<meta name="viewport" content="width=device-width, initial-scale=1, '
        'maximum-scale=1, user-scalable=no">',
      ),
    );
    expect(
      html,
      contains(
        'apple-mobile-web-app-status-bar-style" content="black-translucent"',
      ),
    );
    expect(html, contains('<meta name="theme-color" content="#eef1e8">'));
  });

  test('Safari never zooms on a field: inputs are 16px', () {
    expect(
      html,
      contains('input, textarea, select { font-size: 16px !important; }'),
    );
  });

  // SafeAreaFromPage stays: without viewport-fit=cover the page's insets
  // read 0 and it changes nothing; it still merges real insets correctly.
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
