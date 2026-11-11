import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android manifest checks (AUDIT-R11).
void main() {
  String manifest() =>
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('D3 (R11-6): a push tap opens the app', () {
    // movera-server src/push/fcm.ts sends every Android notification with
    // click_action FLUTTER_NOTIFICATION_CLICK; Android opens only an
    // activity with that action in an intent filter, else the tap does
    // nothing.
    final xml = manifest();
    final filter = RegExp(
      r'<intent-filter>\s*<action\s+android:name="FLUTTER_NOTIFICATION_CLICK"\s*/>\s*'
      r'<category\s+android:name="android.intent.category.DEFAULT"\s*/>\s*'
      r'</intent-filter>',
    );
    expect(filter.hasMatch(xml), isTrue);
  });
}
