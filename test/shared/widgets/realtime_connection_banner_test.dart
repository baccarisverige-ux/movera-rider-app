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

  // Device run 43741532517 (G25 step B): the screen that opens follows its
  // trip in initState, inside a build; the connection tells its listeners
  // at once. The banner of the screen below must take that without
  // "setState() called during build", and show it right after the frame.
  testWidgets('a connection change made while another widget builds is shown '
      'after that frame (no setState during build)', (tester) async {
    final connection = RealtimeConnection();
    addTearDown(connection.dispose);
    connection.markConnected();
    final opened = ValueNotifier<bool>(false);
    addTearDown(opened.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RealtimeConnectionBanner(connection: connection),
              ValueListenableBuilder<bool>(
                valueListenable: opened,
                builder: (_, open, __) => open
                    ? _SubscribesInInitState(connection)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Reconnecting'), findsNothing);

    opened.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('Reconnecting'), findsOneWidget);
  });
}

class _SubscribesInInitState extends StatefulWidget {
  const _SubscribesInInitState(this.connection);
  final RealtimeConnection connection;

  @override
  State<_SubscribesInInitState> createState() => _SubscribesInInitStateState();
}

class _SubscribesInInitStateState extends State<_SubscribesInInitState> {
  @override
  void initState() {
    super.initState();
    widget.connection.markReconnecting();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
