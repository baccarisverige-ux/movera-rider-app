import 'dart:collection';

import 'package:movera_rider/core/observability/observability.dart';

/// One of the last events before a crash (contract v0.18.157
/// `contract.json#crashCatcher.breadcrumbs`): a screen change, an app state
/// change, a failed platform call, a failed API call or a warning log line.
class CrashBreadcrumb {
  const CrashBreadcrumb(this.at, this.type, this.message);

  final DateTime at;
  final String type;
  final String message;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'type': type,
    'message': message,
  };

  static CrashBreadcrumb? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    final type = raw['type'];
    final message = raw['message'];
    if (at == null || type is! String || message is! String) return null;
    if (!CrashBreadcrumbs.types.contains(type)) return null;
    return CrashBreadcrumb(at, type, message);
  }
}

/// The ring buffer of the last [max] breadcrumbs. Each message is scrubbed
/// (no e-mail, phone number or coordinate) and cut to [maxMessage]
/// characters before it is kept. [onChange] lets the crash catcher keep a
/// copy in a file, so a native crash still has them at the next launch.
class CrashBreadcrumbs {
  CrashBreadcrumbs({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const max = 30;
  static const maxMessage = 200;
  static const types = {'route', 'lifecycle', 'platform', 'network', 'log'};

  /// The app's one list (the observer, the log and the API client add to it).
  static CrashBreadcrumbs instance = CrashBreadcrumbs();

  final DateTime Function() _clock;
  final ListQueue<CrashBreadcrumb> _items = ListQueue<CrashBreadcrumb>();

  /// Called after every change (the crash catcher writes the file).
  void Function()? onChange;

  List<CrashBreadcrumb> get items => List.unmodifiable(_items);

  /// The last screen a `route` breadcrumb named, if any.
  String? get lastScreen {
    for (final item in _items.toList().reversed) {
      if (item.type == 'route') return item.message;
    }
    return null;
  }

  void add(String type, String message) {
    if (!types.contains(type)) return;
    try {
      var text = Observability.scrubText(message).trim();
      if (text.isEmpty) return;
      if (text.length > maxMessage) text = text.substring(0, maxMessage);
      _items.addLast(CrashBreadcrumb(_clock(), type, text));
      while (_items.length > max) {
        _items.removeFirst();
      }
      onChange?.call();
    } catch (_) {
      // A breadcrumb must never crash the app.
    }
  }

  void route(String? name) {
    if (name != null && name.isNotEmpty) add('route', withoutIds(name));
  }

  /// A failed API call: method, path with ids replaced and the status.
  void network(String method, String path, Object? status) {
    add(
      'network',
      '${method.toUpperCase()} ${withoutIds(path.split('?').first)} ${status ?? 'timeout'}',
    );
  }

  /// Replaces ids and numbers in a path or route name with `:id`.
  static String withoutIds(String value) => value.replaceAll(
    RegExp(
      r'(?=[0-9a-fA-F-]*\d)[0-9a-fA-F-]{8,}|[a-z]{3}_[0-9A-Za-z]{10,}|\d+',
    ),
    ':id',
  );

  void replaceAll(Iterable<CrashBreadcrumb> items) {
    _items
      ..clear()
      ..addAll(items.take(max));
  }

  void clear() => _items.clear();

  List<Map<String, Object?>> toJson() => [
    for (final item in _items) item.toJson(),
  ];
}
