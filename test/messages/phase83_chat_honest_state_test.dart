import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';

void main() {
  testWidgets(
    'chat keeps draft and never fabricates sent state without transport',
    (tester) async {
      final controller = MessagesController();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
            home: Chat(
              driverName: 'Driver',
              rideId: 'ride-83',
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(MessagesController.sendUnavailableMessage),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'I am outside');
      await tester.pump();

      expect(find.text('I am outside'), findsOneWidget);
      expect(find.bySemanticsLabel('Send message unavailable'), findsOneWidget);
      expect(controller.messages, isEmpty);
      expect(controller.send('I am outside'), isFalse);
      expect(controller.messages, isEmpty);
      expect(find.text('I am outside'), findsOneWidget);
    },
  );
}
