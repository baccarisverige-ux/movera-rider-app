import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/browser_token_store.dart';

/// Owner decision 2026-10-26: on the web the rider stays signed in after the
/// tab or the Home-screen app is fully closed, and signing out still removes
/// everything. A browser's localStorage outlives the tab; its sessionStorage
/// does not. These fakes model that: closing the tab keeps the same
/// localStorage and starts an empty sessionStorage.
class _FakeStorage implements BrowserStorage {
  final values = <String, String>{};
  bool refuseWrites = false;

  @override
  String? getItem(String key) => values[key];

  @override
  void setItem(String key, String value) {
    if (refuseWrites) throw StateError('QuotaExceededError');
    values[key] = value;
  }

  @override
  void removeItem(String key) => values.remove(key);
}

const _access = BrowserTokenStore.accessKey;
const _refresh = BrowserTokenStore.refreshKey;

void main() {
  late _FakeStorage local;
  late _FakeStorage session;
  late BrowserTokenStore store;

  setUp(() {
    local = _FakeStorage();
    session = _FakeStorage();
    store = BrowserTokenStore(persistent: local, legacy: session);
  });

  /// The tab or the installed app is closed and opened again: the same
  /// localStorage, a new empty sessionStorage, a new app instance.
  BrowserTokenStore reopen() {
    session = _FakeStorage();
    return BrowserTokenStore(persistent: local, legacy: session);
  }

  test('the sign-in survives fully closing the tab or app', () async {
    await store.save(access: 'a1', refresh: 'r1');
    final reopened = reopen();
    expect(await reopened.readAccess(), 'a1');
    expect(await reopened.readRefresh(), 'r1');
  });

  test('tokens are written to localStorage, not sessionStorage', () async {
    await store.save(access: 'a1', refresh: 'r1');
    expect(local.values, {_access: 'a1', _refresh: 'r1'});
    expect(session.values, isEmpty);
  });

  test('a rider signed in before the update stays signed in', () async {
    session.values
      ..[_access] = 'old-a'
      ..[_refresh] = 'old-r';
    expect(await store.readAccess(), 'old-a');
    expect(await store.readRefresh(), 'old-r');
    // Moved, not copied: the session now survives closing the tab.
    expect(local.values, {_access: 'old-a', _refresh: 'old-r'});
    expect(session.values, isEmpty);
    final reopened = reopen();
    expect(await reopened.readRefresh(), 'old-r');
  });

  test('a newer session in localStorage wins over an old tab copy', () async {
    local.values
      ..[_access] = 'new-a'
      ..[_refresh] = 'new-r';
    session.values
      ..[_access] = 'old-a'
      ..[_refresh] = 'old-r';
    expect(await store.readAccess(), 'new-a');
    expect(await store.readRefresh(), 'new-r');
    expect(session.values, isEmpty);
  });

  test('a save after the move leaves no copy in sessionStorage', () async {
    session.values
      ..[_access] = 'old-a'
      ..[_refresh] = 'old-r';
    await store.save(access: 'a2', refresh: 'r2');
    expect(local.values, {_access: 'a2', _refresh: 'r2'});
    expect(session.values, isEmpty);
  });

  test('sign-out removes the tokens from both storages', () async {
    local.values
      ..[_access] = 'a'
      ..[_refresh] = 'r'
      ..['flutter.movera_app_language'] = '"en"';
    session.values
      ..[_access] = 'old-a'
      ..[_refresh] = 'old-r';
    await store.clear();
    expect(local.values, {'flutter.movera_app_language': '"en"'});
    expect(session.values, isEmpty);
    expect(await store.readAccess(), isNull);
    expect(await store.readRefresh(), isNull);
    expect(await reopen().readAccess(), isNull);
  });

  test('sign-out still clears localStorage when sessionStorage throws',
      () async {
    final broken = _ThrowingStorage();
    final store = BrowserTokenStore(persistent: local, legacy: broken);
    local.values
      ..[_access] = 'a'
      ..[_refresh] = 'r';
    await expectLater(store.clear(), throwsA(isA<StateError>()));
    expect(local.values, isEmpty);
  });

  test('when localStorage refuses writes the tab keeps the session', () async {
    local.refuseWrites = true;
    await store.save(access: 'a1', refresh: 'r1');
    expect(local.values, isEmpty);
    expect(await store.readAccess(), 'a1');
    expect(await store.readRefresh(), 'r1');
    // Once localStorage takes writes again, the session moves over.
    local.refuseWrites = false;
    expect(await store.readRefresh(), 'r1');
    expect(local.values, {_access: 'a1', _refresh: 'r1'});
    expect(session.values, isEmpty);
  });

  test('a refused move keeps reading the tab copy, never half of it',
      () async {
    session.values
      ..[_access] = 'old-a'
      ..[_refresh] = 'old-r';
    local.refuseWrites = true;
    expect(await store.readAccess(), 'old-a');
    expect(await store.readRefresh(), 'old-r');
    expect(local.values, isEmpty);
  });

  test('the browser build wires localStorage as the store and '
      'sessionStorage only as the old copy', () {
    final src = File(
      'lib/core/auth/web_session_token_store_web.dart',
    ).readAsStringSync();
    expect(
      src,
      contains('persistent: _WebStorage(() => web.window.localStorage)'),
    );
    expect(
      src,
      contains('legacy: _WebStorage(() => web.window.sessionStorage)'),
    );
  });
}

class _ThrowingStorage implements BrowserStorage {
  @override
  String? getItem(String key) => throw StateError('SecurityError');

  @override
  void setItem(String key, String value) => throw StateError('SecurityError');

  @override
  void removeItem(String key) => throw StateError('SecurityError');
}
