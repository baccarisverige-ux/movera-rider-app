import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';

void main() {
  test('realtime connection exposes observable state changes', () async {
    final connection = RealtimeConnection();
    addTearDown(connection.dispose);

    final seen = <RealtimeState>[];
    final sub = connection.states.listen(seen.add);
    addTearDown(sub.cancel);

    connection.state = RealtimeState.connecting;
    connection.markConnected();
    connection.markDisconnected();
    connection.markReconnecting();
    connection.markFailed();

    expect(seen, <RealtimeState>[
      RealtimeState.connecting,
      RealtimeState.connected,
      RealtimeState.disconnected,
      RealtimeState.reconnecting,
      RealtimeState.failed,
    ]);
  });

  testWidgets('connection banner reflects loss, reconnect and recovery', (
    tester,
  ) async {
    final connection = RealtimeConnection();
    addTearDown(connection.dispose);
    connection.markConnected();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RealtimeConnectionBanner(connection: connection)),
      ),
    );

    expect(find.text('Connection lost'), findsNothing);
    expect(find.text('Reconnecting'), findsNothing);

    connection.markDisconnected();
    await tester.pump();
    expect(find.text('Connection lost'), findsOneWidget);
    expect(
      find.text('Live ride updates are temporarily unavailable.'),
      findsOneWidget,
    );

    connection.markReconnecting();
    await tester.pump();
    expect(find.text('Reconnecting'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    connection.markConnected();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Connection lost'), findsNothing);
    expect(find.text('Reconnecting'), findsNothing);
  });
}
