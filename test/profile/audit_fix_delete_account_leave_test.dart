import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/profile/application/account_deletion_controller.dart';
import 'package:movera_rider/features/profile/presentation/delete_account.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u152: leaving Delete account while the request was in flight
/// still signed the rider out and wiped the device, but nothing routed to
/// Sign in: the rider was left on Account/Home with no session.

/// The server takes its time; the request then ends the session as the
/// real controller does.
class _SlowDeletion extends AccountDeletionController {
  final answer = Completer<void>();

  @override
  Future<void> requestDeletion() async {
    await answer.future;
    await AppScope.instance.auth.signOutLocally();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_SlowDeletion> _sendDeletion(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await AppScope.instance.tokens.save(access: 'a', refresh: 'b');
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: RideRestoreGate(key: RideRestoreGate.gateKey),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  final deletion = _SlowDeletion();
  moveraNavigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => DeleteAccountPage(controller: deletion),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  final send = find.text('Delete my account');
  await tester.scrollUntilVisible(
    send,
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(send);
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
  await _settle(tester);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  return deletion;
}

Future<void> _answer(WidgetTester tester, _SlowDeletion deletion) async {
  deletion.answer.complete();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  RideRestoreCoordinator.instance.showing = RestoredSurface.home;
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_profile_v1': '{"name":"Rider A"}',
    });
  });

  testWidgets('Back waits while the deletion request is sent', (tester) async {
    final deletion = await _sendDeletion(tester);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.byType(DeleteAccountPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(DeleteAccountPage), findsOneWidget);

    await _answer(tester, deletion);
    expect(find.text('Your deletion request was sent'), findsOneWidget);
    expect(await AppScope.instance.auth.hasSession(), isFalse);
    await _unmount(tester);
  });

  testWidgets('a page closed during the request still ends on Sign in', (
    tester,
  ) async {
    final deletion = await _sendDeletion(tester);

    // Something else closed the page (it cannot be popped by the rider).
    moveraNavigatorKey.currentState!.pop();
    await _settle(tester);
    expect(find.byType(DeleteAccountPage), findsNothing);

    await _answer(tester, deletion);
    expect(await AppScope.instance.auth.hasSession(), isFalse);
    expect(find.byType(SignIn), findsOneWidget);
    await _unmount(tester);
  });
}
