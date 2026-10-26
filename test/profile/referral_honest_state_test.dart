import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/profile/presentation/refer_and_earn.dart';

void main() {
  testWidgets('referral surface shows a designed honest unavailable state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: ReferAndEarn()),
      ),
    );

    expect(find.byIcon(Icons.group_add_outlined), findsOneWidget);
    expect(find.text('Referrals aren’t available yet'), findsOneWidget);
    expect(
      find.textContaining('when the Movera referral programme launches'),
      findsOneWidget,
    );
    expect(find.textContaining(r'$5'), findsNothing);
    expect(find.textContaining('Referral code copied'), findsNothing);
  });
}
