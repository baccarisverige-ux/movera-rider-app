import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/browser_token_store.dart';

class _Storage implements BrowserStorage {
  final Map<String, String> items = {};
  bool refuseWrites = false;

  @override
  String? getItem(String key) => items[key];

  @override
  void setItem(String key, String value) {
    if (refuseWrites) throw StateError('QuotaExceededError');
    items[key] = value;
  }

  @override
  void removeItem(String key) => items.remove(key);
}

/// Contract v0.18.5, owner G1-D1 "Stay signed in (Recommended)": the rider
/// web keeps the session after the tab is closed, like the driver app.
void main() {
  test('closing the tab keeps the rider signed in', () async {
    final local = _Storage();
    await BrowserTokenStore(
      persistent: local,
      legacy: _Storage(),
    ).save(access: 'a1', refresh: 'r1');

    // A new tab: sessionStorage starts empty, localStorage is the same.
    final reopened = BrowserTokenStore(persistent: local, legacy: _Storage());
    expect(await reopened.readAccess(), 'a1');
    expect(await reopened.readRefresh(), 'r1');
  });

  test(
    'a session saved by an earlier build (sessionStorage) is moved over',
    () async {
      final local = _Storage();
      final tab = _Storage()
        ..items[BrowserTokenStore.accessKey] = 'old-a'
        ..items[BrowserTokenStore.refreshKey] = 'old-r';
      final store = BrowserTokenStore(persistent: local, legacy: tab);
      expect(await store.readRefresh(), 'old-r');
      expect(local.items[BrowserTokenStore.refreshKey], 'old-r');
      expect(tab.items, isEmpty);
    },
  );

  test('sign-out removes the session from both storages', () async {
    final local = _Storage();
    final tab = _Storage();
    final store = BrowserTokenStore(persistent: local, legacy: tab);
    await store.save(access: 'a', refresh: 'r');
    tab.items[BrowserTokenStore.accessKey] = 'stale';
    await store.clear();
    expect(local.items, isEmpty);
    expect(tab.items, isEmpty);
    expect(await store.readAccess(), isNull);
  });

  test('localStorage refusing writes keeps the session for the tab', () async {
    final local = _Storage()..refuseWrites = true;
    final tab = _Storage();
    final store = BrowserTokenStore(persistent: local, legacy: tab);
    await store.save(access: 'a', refresh: 'r');
    expect(await store.readAccess(), 'a');
  });

  test('the web build uses localStorage, sessionStorage only to move over', () {
    // Before G1-D1 the rider web kept the session in sessionStorage only,
    // so a closed tab signed the rider out.
    final source = File(
      'lib/core/auth/web_session_token_store_web.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('persistent: _WebStorage(() => web.window.localStorage)'),
    );
    expect(
      source,
      contains('legacy: _WebStorage(() => web.window.sessionStorage)'),
    );
  });
}
