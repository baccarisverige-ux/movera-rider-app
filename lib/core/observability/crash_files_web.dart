import 'package:movera_rider/core/observability/crash_files.dart';

/// The web keeps no marker (a closed tab is not a crash).
Future<CrashFiles?> openCrashFiles() async => null;

String? fallbackOsVersion() => null;

void listenToIsolateErrors(
  void Function(Object error, StackTrace stack) onError,
) {}

const bool crashMarkerSupported = false;
