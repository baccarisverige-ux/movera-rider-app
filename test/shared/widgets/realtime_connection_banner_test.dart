import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';

void main() {
  testWidgets(
    'connection banner reflects transport truth and hides when connected',
    (tester) async {
      final connection = RealtimeConnection();
      addTearDown(connection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeConnectionBanner(connection: connection),
          ),
        ),
      );

      expect(find.text('Connection lost'), findsOneWidget);

      connection.markConnected();
      await tester.pumpAndSettle();
      expect(find.text('Connection lost'), findsNothing);
      expect(find.text('Reconnecting'), findsNothing);

      connection.markReconnecting();
      await tester.pump();
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(
        find.text('Ride details stay on screen while connection returns.'),
        findsOneWidget,
      );

      connection.markFailed();
      await tester.pump();
      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    },
  );
}
