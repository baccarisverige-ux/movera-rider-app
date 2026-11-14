import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';

void main() {
  testWidgets('tip stays limited to fixed propositions', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RideCompletedAddTip()),
          ),
        ),
      ),
    );

    expect(find.text('10 kr'), findsOneWidget);
    expect(find.text('20 kr'), findsOneWidget);
    expect(find.text('30 kr'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('custom-tip-field')),
      findsNothing,
    );
    expect(find.text('Custom amount'), findsNothing);
    expect(find.text('Enter amount'), findsNothing);

    await tester.tap(find.text('20 kr'));
    await tester.pump();

    expect(find.text('20,00 kr selected.'), findsOneWidget);

    await tester.tap(find.text('20 kr'));
    await tester.pump();

    expect(find.text('Tip is optional.'), findsOneWidget);
  });
}
