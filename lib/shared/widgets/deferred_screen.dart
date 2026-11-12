import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/core/web/web_reload.dart';
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

  /// Whether a failed load means "the app was republished" (web) rather
  /// than "try the download again" (phones). Tests switch it.
  @visibleForTesting
  static bool isWeb = kIsWeb;

  /// Web: reloads the page once per few minutes; true when it started.
  @visibleForTesting
  static bool Function() reloadOnce = reloadPageForNewVersion;

  /// Web Retry: reloads the page now (after refreshing the cached app
  /// shell); true when it started.
  @visibleForTesting
  static bool Function() reloadNow = reloadPageNow;

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
        // Web: a publish while this page was open replaced the screen's
        // part under the same name, and loading it again fetches the same
        // rejected file (2026-11-11). A fresh page loads the new app; the
        // spinner stays while the page goes.
        if (DeferredScreen.isWeb && DeferredScreen.reloadOnce()) return;
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  void _retry() {
    // Web: the reload first downloads the app shell fresh (a few seconds at
    // most); the spinner shows meanwhile instead of the retry icon.
    final reloading = DeferredScreen.isWeb && DeferredScreen.reloadNow();
    setState(() => _failed = false);
    if (!reloading) _start();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    if (_failed) {
      // A way back out when the part could not be downloaded.
      return Scaffold(
        key: const ValueKey('deferred-screen-loading'),
        appBar: AppBar(
          leading: const BackButton(key: ValueKey('deferred-screen-back')),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: Center(
          child: IconButton(
            key: const ValueKey('deferred-screen-retry'),
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh_rounded),
            iconSize: 32,
            onPressed: _retry,
          ),
        ),
      );
    }
    return Material(
      key: const ValueKey('deferred-screen-loading'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: const SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
