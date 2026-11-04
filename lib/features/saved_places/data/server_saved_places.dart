import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';

/// BASE B13 (contract v0.18.26 §47, `contract.json#phoneDataToServer`;
/// owner 2026-11-03 "Phone-only data: Yes, all to server"): the rider's
/// saved places live on the server. The phone keeps a copy only to show
/// something offline.
///
/// - [sync] (after sign-in and at launch with a session): the first time on
///   this account it uploads the places the phone kept before
///   (`POST /rider/places/import`, applied once by the server), then reads
///   `GET /rider/places` and writes them to the phone copy. Home and Saved
///   Places follow the phone copy's change stream, so no screen changes.
/// - Every later change of the phone copy (Home or Saved Places) is sent as
///   the difference to what the server last said: POST a new place, PUT a
///   changed one, DELETE a removed one. Home and Work are one slot each.
class ServerSavedPlaces {
  ServerSavedPlaces({required ApiClient api, HomeAddressRepository? store})
    : _api = api,
      _store = store ?? HomeAddressRepository();

  final ApiClient _api;
  final HomeAddressRepository _store;

  /// Set once this account's phone places were uploaded (a `movera_` key, so
  /// sign-out removes it with the rest of the rider's data).
  static const uploadedKey = 'movera_saved_places_uploaded';
  static const _path = '/api/v1/rider/places';

  /// What the server holds, by placeId; null until the first read.
  Map<String, ServerPlace>? _known;
  StreamSubscription<void>? _watch;
  Future<void> _queue = Future<void>.value();

  /// Pull (with the one-time upload), then keep sending phone changes.
  Future<void> sync() {
    _watch ??= _store.changes.listen((_) => _enqueue(_push));
    return _enqueue(_pull);
  }

  /// Completes when every queued pull and push is done (tests).
  Future<void> get idle => _queue;

  /// Sign-out: forget what the server said and stop sending.
  void reset() {
    _known = null;
    unawaited(_watch?.cancel());
    _watch = null;
  }

  Future<void> _enqueue(Future<void> Function() step) {
    final next = _queue.then((_) => step()).catchError((Object error) {
      // Offline or refused: the phone copy stays; the next sync tries again.
      AppLog.warning(
        'saved_places.sync_failed',
        extra: {'error': error.runtimeType.toString()},
      );
    });
    _queue = next;
    return next;
  }

  Future<void> _pull() async {
    final prefs = await PreferencesStore.load();
    Map<String, dynamic> answer;
    if (prefs.getString(uploadedKey) != '1') {
      final local = await _store.load();
      answer = await _api.post(
        '$_path/import',
        body: {'items': requestsFor(local)},
      );
      await prefs.setString(uploadedKey, '1');
    } else {
      answer = await _api.get(_path);
    }
    final places = ServerPlace.listFrom(answer);
    _known = {for (final p in places) p.placeId: p};
    final local = await _store.load();
    await _store.save(snapshotFor(places, recent: local.recent));
  }

  Future<void> _push() async {
    final known = _known;
    if (known == null) return;
    final local = await _store.load();
    final plan = planChanges(known.values.toList(), local);
    if (plan.isEmpty) return;
    for (final id in plan.deletes) {
      await _api.delete('$_path/${Uri.encodeComponent(id)}');
      known.remove(id);
    }
    for (final change in plan.updates) {
      final saved = ServerPlace.from(
        await _api.put(
          '$_path/${Uri.encodeComponent(change.placeId)}',
          body: change.body,
        ),
      );
      if (saved != null) known[saved.placeId] = saved;
    }
    var newIds = false;
    for (final create in plan.creates) {
      final saved = ServerPlace.from(await _api.post(_path, body: create.body));
      if (saved == null) continue;
      known.removeWhere((_, p) => p.kind != 'other' && p.kind == saved.kind);
      known[saved.placeId] = saved;
      if (saved.kind == 'other') newIds = true;
    }
    // A new custom place takes the server's id on the phone too, so the
    // next change of it is a PUT, not a second place.
    if (newIds) {
      await _store.save(
        snapshotFor(known.values.toList(), recent: local.recent),
      );
    }
  }
}

/// One saved place as the server sends it.
class ServerPlace {
  const ServerPlace({
    required this.placeId,
    required this.kind,
    required this.label,
    required this.address,
    this.type,
  });

  final String placeId;

  /// home | work | other.
  final String kind;
  final String label;
  final String address;
  final String? type;

  static ServerPlace? from(Map<String, dynamic> json) {
    final id = json['placeId'];
    final kind = json['kind'];
    final label = json['label'];
    final place = json['place'];
    final address = place is Map ? place['address'] : null;
    if (id is! String || kind is! String || label is! String) return null;
    if (address is! String || address.trim().isEmpty) return null;
    final type = json['type'];
    return ServerPlace(
      placeId: id,
      kind: kind,
      label: label,
      address: address,
      type: type is String ? type : null,
    );
  }

  static List<ServerPlace> listFrom(Map<String, dynamic> page) {
    final items = page['items'];
    if (items is! List) return const <ServerPlace>[];
    return [
      for (final item in items)
        if (item is Map<String, dynamic> && ServerPlace.from(item) != null)
          ServerPlace.from(item)!,
    ];
  }
}

final RegExp _typePattern = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');

/// The phone's word for a custom place, as the server takes it.
String? serverTypeFor(String? type) {
  final clean = (type ?? '').trim().toLowerCase();
  return _typePattern.hasMatch(clean) ? clean : null;
}

Map<String, dynamic> _body({
  required String label,
  required String kind,
  required String address,
  String? type,
}) {
  final cleanLabel = label.trim().isEmpty ? (type ?? kind) : label.trim();
  return {
    'label': cleanLabel.length > 80 ? cleanLabel.substring(0, 80) : cleanLabel,
    'kind': kind,
    if (kind == 'other' && serverTypeFor(type) != null)
      'type': serverTypeFor(type),
    'place': {'address': address.trim()},
  };
}

/// The phone's places as `SavedPlaceRequest`s (the one-time upload).
List<Map<String, dynamic>> requestsFor(HomeAddressSnapshot local) => [
  if ((local.home ?? '').trim().isNotEmpty)
    _body(label: 'Home', kind: 'home', address: local.home!),
  if ((local.work ?? '').trim().isNotEmpty)
    _body(label: 'Work', kind: 'work', address: local.work!),
  for (final place in local.places)
    if ((place['address'] ?? '').trim().isNotEmpty)
      _body(
        label: place['title'] ?? '',
        kind: 'other',
        type: place['type'],
        address: place['address']!,
      ),
];

/// The server's places as the phone copy (custom places keep the server id).
HomeAddressSnapshot snapshotFor(
  List<ServerPlace> places, {
  List<String> recent = const <String>[],
}) {
  String? home;
  String? work;
  final others = <Map<String, String>>[];
  for (final p in places) {
    if (p.kind == 'home') {
      home = p.address;
    } else if (p.kind == 'work') {
      work = p.address;
    } else {
      others.add({
        'id': p.placeId,
        'title': p.label,
        'type': p.type ?? 'other',
        'address': p.address,
      });
    }
  }
  return HomeAddressSnapshot(
    home: home,
    work: work,
    recent: recent,
    places: others,
  );
}

class PlaceCreate {
  const PlaceCreate(this.body, {this.localId});
  final Map<String, dynamic> body;
  final String? localId;
}

class PlaceUpdate {
  const PlaceUpdate(this.placeId, this.body);
  final String placeId;
  final Map<String, dynamic> body;
}

class PlacePlan {
  const PlacePlan({
    this.creates = const [],
    this.updates = const [],
    this.deletes = const [],
  });
  final List<PlaceCreate> creates;
  final List<PlaceUpdate> updates;
  final List<String> deletes;
  bool get isEmpty => creates.isEmpty && updates.isEmpty && deletes.isEmpty;
}

/// What to send so the server matches the phone copy [local], given what the
/// server last said ([known]).
PlacePlan planChanges(List<ServerPlace> known, HomeAddressSnapshot local) {
  final creates = <PlaceCreate>[];
  final updates = <PlaceUpdate>[];
  final deletes = <String>[];
  for (final slot in const ['home', 'work']) {
    final address = (slot == 'home' ? local.home : local.work)?.trim() ?? '';
    final server = known.where((p) => p.kind == slot).firstOrNull;
    if (address.isEmpty) {
      if (server != null) deletes.add(server.placeId);
    } else if (server == null || server.address.trim() != address) {
      creates.add(
        PlaceCreate(
          _body(
            label: slot == 'home' ? 'Home' : 'Work',
            kind: slot,
            address: address,
          ),
        ),
      );
    }
  }
  final others = {
    for (final p in known)
      if (p.kind == 'other') p.placeId: p,
  };
  final kept = <String>{};
  for (final place in local.places) {
    final address = (place['address'] ?? '').trim();
    if (address.isEmpty) continue;
    final id = (place['id'] ?? '').trim();
    final body = _body(
      label: place['title'] ?? '',
      kind: 'other',
      type: place['type'],
      address: address,
    );
    final server = others[id];
    if (server == null) {
      creates.add(PlaceCreate(body, localId: id.isEmpty ? null : id));
      continue;
    }
    kept.add(id);
    if (server.address.trim() != address ||
        server.label != body['label'] ||
        server.type != body['type']) {
      updates.add(PlaceUpdate(id, body));
    }
  }
  for (final id in others.keys) {
    if (!kept.contains(id)) deletes.add(id);
  }
  return PlacePlan(creates: creates, updates: updates, deletes: deletes);
}
