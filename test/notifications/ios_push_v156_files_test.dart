import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v0.18.156 (owner 2026-11-24 "Notifications doesn't work on iPhones?";
/// contract `auth.devices.config.ios`): the server now gives `iosConfig`
/// (rider bundle id com.movera.rider). The iPhone build must carry the
/// push background mode and aps-environment, and the TestFlight export
/// must keep aps-environment production (build 10 had none, so APNs
/// refused every token). No GoogleService-Info.plist in the repository.
void main() {
  test('contract: the rider iOS bundle id and iosConfig shape', () {
    final contract =
        jsonDecode(File('contracts/contract.json').readAsStringSync())
            as Map<String, dynamic>;
    final ios =
        (((contract['auth'] as Map)['devices'] as Map)['config'] as Map)['ios']
            as Map;
    expect((ios['iosBundleIds'] as Map)['rider'], 'com.movera.rider');
    expect(
      ios['note'],
      contains('iosConfig? { apiKey, appId, messagingSenderId, projectId'),
    );
  });

  test('iOS files: remote-notification, aps-environment, export guard', () {
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<string>remote-notification</string>'),
    );
    expect(
      File('ios/Runner/Runner.entitlements').readAsStringSync(),
      contains('<key>aps-environment</key>'),
    );
    expect(
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
    );
    expect(File('ios/Runner/GoogleService-Info.plist').existsSync(), isFalse);
    final workflow = File(
      '.github/workflows/ios-testflight.yml',
    ).readAsStringSync();
    expect(workflow, contains('Set :aps-environment production'));
    expect(workflow, contains('--entitlements "\$ent" "\$app"'));
    expect(workflow, contains('aps-environment production (push would never'));
  });
}
