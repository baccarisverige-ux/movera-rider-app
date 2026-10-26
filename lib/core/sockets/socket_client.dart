import 'package:movera_rider/core/realtime/realtime_connection.dart';

class SocketClient {
  SocketClient(this.connection);
  final RealtimeConnection connection;

  Future<void> connect() async {
    connection.state = RealtimeState.connecting;
    connection.markConnected();
  }

  Future<void> reconnect() async {
    connection.state = RealtimeState.reconnecting;
    await Future<void>.delayed(connection.nextBackoff());
    connection.markConnected();
  }
}
