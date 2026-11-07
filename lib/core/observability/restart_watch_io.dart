import 'package:movera_rider/core/observability/restart_watch.dart';

/// Not on the web: no page that iOS can kill, so no watch.
RestartWatch? startRestartWatch({required RestartReport report}) => null;
