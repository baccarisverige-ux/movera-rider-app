import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/secure_token_store.dart';
import 'package:movera_rider/core/auth/token_store.dart';

class _FakeKeychain implements SecureKeyValue {
  final values = <String, String>{};
  final writes = <String>[];

  /// Runs once, just before [key] is read (a save landing mid-read).
  String? beforeReadOf;
  Future<void> Function()? beforeRead;

  @override
  Future<String?> read(String key) async {
    final hook = beforeRead;
    if (hook != null && key == beforeReadOf) {
      beforeRead = null;
      await hook();
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('memory override roundtrip', () async {
    final store = SecureTokenStore(override: MemoryTokenStore());
    await store.save(access: 'a', refresh: 'r');
    expect(await store.readAccess(), 'a');
    expect(await store.readRefresh(), 'r');
    await store.clear();
    expect(await store.readAccess(), isNull);
  });

  test('native save is one write holding both tokens', () async {
    final keychain = _FakeKeychain();
    final store = NativeSecureTokenStore(keychain);
    await store.save(access: 'a2', refresh: 'r2');
    expect(keychain.writes, [SecureTokenStore.sessionKey]);
    expect(keychain.values.keys, [SecureTokenStore.sessionKey]);
    expect(jsonDecode(keychain.values[SecureTokenStore.sessionKey]!), {
      'access': 'a2',
      'refresh': 'r2',
    });
    expect(await store.readAccess(), 'a2');
    expect(await store.readRefresh(), 'r2');
  });

  test('a session saved by an older build (two keys) is migrated', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.accessKey] = 'old-a'
      ..values[SecureTokenStore.refreshKey] = 'old-r';
    final store = NativeSecureTokenStore(keychain);
    expect(await store.readAccess(), 'old-a');
    expect(await store.readRefresh(), 'old-r');
    // The next rotation moves the session to the one-entry format.
    await store.save(access: 'new-a', refresh: 'new-r');
    expect(keychain.values.keys, [SecureTokenStore.sessionKey]);
    expect(await store.readAccess(), 'new-a');
    expect(await store.readRefresh(), 'new-r');
  });

  test('a half-written old session is no session', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.accessKey] = 'old-a';
    final store = NativeSecureTokenStore(keychain);
    expect(await store.readAccess(), isNull);
    expect(await store.readRefresh(), isNull);
  });

  test('a read racing a save never puts the old tokens back', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.accessKey] = 'old-a'
      ..values[SecureTokenStore.refreshKey] = 'old-r';
    final reader = NativeSecureTokenStore(keychain);
    final writer = NativeSecureTokenStore(keychain);
    final read = reader.readRefresh();
    final save = writer.save(access: 'new-a', refresh: 'new-r');
    await Future.wait([read, save]);
    expect(await reader.readAccess(), 'new-a');
    expect(await reader.readRefresh(), 'new-r');
  });

  test('an old pair moved over mid-read is read from the new entry', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.accessKey] = 'old-a'
      ..values[SecureTokenStore.refreshKey] = 'old-r';
    final store = NativeSecureTokenStore(keychain);
    keychain
      ..beforeReadOf = SecureTokenStore.refreshKey
      ..beforeRead = () => store.save(access: 'new-a', refresh: 'new-r');
    expect(await store.readRefresh(), 'new-r');
  });

  test('sign-out clears both formats', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.sessionKey] = '{"access":"a","refresh":"r"}'
      ..values[SecureTokenStore.accessKey] = 'old-a'
      ..values[SecureTokenStore.refreshKey] = 'old-r';
    final store = NativeSecureTokenStore(keychain);
    await store.clear();
    expect(keychain.values, isEmpty);
    expect(await store.readAccess(), isNull);
  });

  test('an unreadable entry reads as signed out', () async {
    final keychain = _FakeKeychain()
      ..values[SecureTokenStore.sessionKey] = 'not json';
    final store = NativeSecureTokenStore(keychain);
    expect(await store.readAccess(), isNull);
  });
}
