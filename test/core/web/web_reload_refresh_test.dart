import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/web/web_reload.dart';

/// 2026-11-11 (owner "Yes, fix it", reload proof): GitHub Pages lets the
/// browser keep main.dart.js for ten minutes, so a plain reload ran the old
/// bundle again and rejected the new screen part a second time. The reload
/// first downloads the app shell fresh into the browser cache.
void main() {
  test('the cache refresh finishes before the page reloads', () async {
    final calls = <String>[];
    final refreshDone = Completer<void>();
    final run = refreshThenReload(
      refresh: () {
        calls.add('refresh started');
        return refreshDone.future.then((_) => calls.add('refresh done'));
      },
      reload: () => calls.add('reload'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['refresh started'], reason: 'no reload before the refresh');
    refreshDone.complete();
    await run;
    expect(calls, ['refresh started', 'refresh done', 'reload']);
  });

  test('a slow refresh still reloads after the timeout', () {
    fakeAsync((async) {
      var reloads = 0;
      refreshThenReload(
        refresh: () => Completer<void>().future,
        reload: () => reloads += 1,
      );
      async.elapse(webReloadRefreshTimeout - const Duration(milliseconds: 1));
      expect(reloads, 0);
      async.elapse(const Duration(milliseconds: 2));
      expect(reloads, 1);
    });
  });

  test('a failed refresh (offline, blocked) still reloads', () async {
    var reloads = 0;
    await refreshThenReload(
      refresh: () => Future<void>.error(StateError('network')),
      reload: () => reloads += 1,
    );
    expect(reloads, 1);
  });

  test('the shell files resolve against the base href', () {
    expect(
      webAppShellUrls(
        Uri.parse('https://example.org/movera-rider-app/live/'),
      ).map((u) => u.toString()),
      [
        'https://example.org/movera-rider-app/live/flutter_bootstrap.js',
        'https://example.org/movera-rider-app/live/main.dart.js',
      ],
    );
  });
}
