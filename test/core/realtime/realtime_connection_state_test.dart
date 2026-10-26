import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';

void main() {
  test('realtime connection publishes transport state changes', () async {
    final connection = RealtimeConnection();
    final seen = <RealtimeState>[];
    final sub = connection.states.listen(seen.add);

    connection.state = RealtimeState.connecting;
    connection.state = RealtimeState.connecting;
    connection.markReconnecting();
    connection.markConnected();
    connection.markDisconnected();
    connection.markFailed();

    expect(seen, <RealtimeState>[
      RealtimeState.connecting,
      RealtimeState.reconnecting,
      RealtimeState.connected,
      RealtimeState.disconnected,
      RealtimeState.failed,
    ]);

    await sub.cancel();
    connection.dispose();
  });

  test('successful reconnect resets exponential backoff', () {
    final connection = RealtimeConnection();

    expect(connection.nextBackoff(), const Duration(seconds: 1));
    expect(connection.nextBackoff(), const Duration(seconds: 2));
    connection.markConnected();
    expect(connection.nextBackoff(), const Duration(seconds: 1));

    connection.dispose();
  });
}
