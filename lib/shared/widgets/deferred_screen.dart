import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// A screen whose code is loaded the first time it opens (owner 2026-11-03,
/// LT-4 "load on open"). On the web the app's first download no longer
/// carries this screen; the first open shows a short spinner while its part
/// of the app downloads, later opens are instant. On phones (and in tests)
/// the load finishes at once.
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({super.key, required this.load, required this.builder});

  /// The library's `loadLibrary`.
  final Future<void> Function() load;

  /// Builds the screen once its library is loaded.
  final WidgetBuilder builder;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    widget.load().then(
      (_) {
        if (mounted) setState(() => _ready = true);
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  void _retry() {
    setState(() => _failed = false);
    _start();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    return Material(
      key: const ValueKey('deferred-screen-loading'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: _failed
            // A dropped connection while the part downloads: tap to try
            // again (the existing "Retry" text, no new words).
            ? IconButton(
                key: const ValueKey('deferred-screen-retry'),
                tooltip: context.l10n.retry,
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 32,
                onPressed: _retry,
              )
            : const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
      ),
    );
  }
}
