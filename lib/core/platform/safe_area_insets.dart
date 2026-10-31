import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/platform/safe_area_insets_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/platform/safe_area_insets_web.dart';

/// The phone's safe-area insets (status bar, notch, home indicator) as the
/// page sees them through CSS `env(safe-area-inset-*)`.
///
/// A store app gets them from the system ([MediaQuery]); the web engine
/// reports `viewPadding` as zero in every browser, so the web build reads
/// them from CSS and [SafeAreaFromPage] puts them into [MediaQuery].
///
/// Owner 2026-10-31 "Go back to before": web/index.html no longer sets
/// `viewport-fit=cover` (the edge-to-edge page of 2026-10-30 is undone), so
/// in the browser these read 0 and [SafeAreaFromPage] changes nothing.
abstract class SafeAreaSource {
  /// The insets now, in logical pixels; [EdgeInsets.zero] off the web.
  EdgeInsets read();

  /// Calls [onChange] when they may have changed (rotation, resize).
  void listen(VoidCallback onChange);

  void dispose();
}

SafeAreaSource createSafeAreaSource() => platformSafeAreaSource();

/// Adds the page's safe-area insets to [MediaQuery.padding] and
/// [MediaQuery.viewPadding] where the engine reported none, so
/// [SafeArea] and `MediaQuery.paddingOf(context).top` work in the browser
/// as in the store apps.
class SafeAreaFromPage extends StatefulWidget {
  const SafeAreaFromPage({super.key, required this.child, this.source});

  final Widget child;

  /// Null: the platform's ([createSafeAreaSource]).
  final SafeAreaSource? source;

  @override
  State<SafeAreaFromPage> createState() => _SafeAreaFromPageState();
}

class _SafeAreaFromPageState extends State<SafeAreaFromPage> {
  late final SafeAreaSource _source = widget.source ?? createSafeAreaSource();
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _insets = _source.read();
    _source.listen(() {
      if (!mounted) return;
      final next = _source.read();
      if (next != _insets) setState(() => _insets = next);
    });
  }

  @override
  void dispose() {
    if (widget.source == null) _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (_insets == EdgeInsets.zero) return widget.child;
    EdgeInsets merge(EdgeInsets engine) => EdgeInsets.fromLTRB(
      engine.left > 0 ? engine.left : _insets.left,
      engine.top > 0 ? engine.top : _insets.top,
      engine.right > 0 ? engine.right : _insets.right,
      // With the keyboard up the bottom inset is the keyboard's business.
      engine.bottom > 0 || media.viewInsets.bottom > 0
          ? engine.bottom
          : _insets.bottom,
    );
    return MediaQuery(
      data: media.copyWith(
        padding: merge(media.padding),
        viewPadding: merge(media.viewPadding),
      ),
      child: widget.child,
    );
  }
}
