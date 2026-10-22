import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.2 parts c+d: messages that claim success they did not get.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps a phone-sized app around [home].
  Future<void> pumpPage(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  /// A Security controller over an API answering GET with [security];
  /// [posts] counts the sign-out requests.
  final posts = <String>[];
  Future<AccountSecurityController> securityWith(
    Map<String, dynamic> security,
  ) async {
    posts.clear();
    final controller = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST') posts.add(request.url.path);
            return http.Response(
              jsonEncode({'code': 'OK', 'security': security}),
              200,
            );
          }),
          env: AppEnv.current,
        ),
      ),
    );
    await controller.load();
    return controller;
  }

  test('rider-u156: a sign-out after the reauthentication window says so',
      () async {
    final security = await securityWith({
      'reauthenticatedAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 6))
          .toIso8601String(),
      'capabilities': {'reauthentication': true, 'signOutOtherDevices': true},
      'sessions': [
        {'id': 's1', 'device': 'This phone', 'current': true},
        {'id': 's2', 'device': 'iPad'},
      ],
    });

    await security.signOutOtherDevices();

    expect(posts, isEmpty);
    expect(security.errorMessage, L10n.current.reauthBeforeRevoke);
  });

  testWidgets('rider-u157: a session without a place has no dangling '
      'separator', (tester) async {
    final security = await securityWith({
      'sessions': [
        {'id': 's1', 'device': 'This phone', 'current': true},
        {'id': 's2', 'device': 'iPad', 'source': 'Web'},
      ],
    });
    await pumpPage(tester, SecurityPage(securityController: security));

    expect(find.text('This session'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
  });
}
