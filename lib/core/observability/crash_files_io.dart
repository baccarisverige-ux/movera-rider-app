import 'dart:io';
import 'dart:isolate';

import 'package:movera_rider/core/observability/crash_files.dart';
import 'package:path_provider/path_provider.dart';

/// The app's support folder (iOS Application Support, Android files): the
/// same folder the native crash handlers write to.
class _IoCrashFiles implements CrashFiles {
  _IoCrashFiles(this.dir);
  final Directory dir;

  File _file(String name) => File('${dir.path}/$name');

  @override
  String? read(String name) {
    try {
      final file = _file(name);
      return file.existsSync() ? file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String name, String text) {
    try {
      _file(name).writeAsStringSync(text, flush: true);
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }

  @override
  void delete(String name) {
    try {
      final file = _file(name);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }
}

/// The phone's crash files, or null when the folder cannot be read.
Future<CrashFiles?> openCrashFiles() async {
  try {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _IoCrashFiles(dir);
  } catch (_) {
    return null;
  }
}

/// The OS line when the native code wrote none (e.g. "ios 17.1").
String? fallbackOsVersion() {
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return null;
  }
}

/// Uncaught errors of the main isolate that reach no zone or dispatcher.
void listenToIsolateErrors(
  void Function(Object error, StackTrace stack) onError,
) {
  try {
    final port = RawReceivePort((Object? message) {
      if (message is List && message.length == 2) {
        onError(
          message[0] ?? 'Isolate error',
          StackTrace.fromString('${message[1] ?? ''}'),
        );
      }
    });
    Isolate.current.addErrorListener(port.sendPort);
  } catch (_) {
    // Never shown and never fatal: a crash report must not crash the app.
  }
}

/// Native crash files exist only on Android and iOS.
const bool crashMarkerSupported = true;
