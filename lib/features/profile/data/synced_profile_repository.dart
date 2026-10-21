import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/domain/rider_profile_repository.dart';

/// The profile the server knows (FLOW-7). The device copy stays as a cache
/// so screens read it synchronously. The server copy is read with
///
/// `GET /api/v1/rider/profile` → `{profile}` (null for a rider with none)
///
/// on [hydrate] (launch and sign-in) and before the first save, and every
/// save is sent as
///
/// `PATCH /api/v1/rider/profile`
/// `{name, language, consents: {rideUpdates, emailUpdates, promotions}}`
///
/// PROPOSED, needs agreement with Driver, Admin and backend (contract C-12):
/// the driver app shows the rider's first name from it, and the consents are
/// the rider's marketing/notification choices.
///
/// rider-u148: nothing is sent until the server copy has been read, so an
/// empty device copy (after a sign-out, or on a new device) never blanks
/// the rider's name or resets their consents on the server. A blank name is
/// never sent. The fields the rider changed before the server copy was read
/// are kept on the device, marked [syncPending], laid over the server copy
/// once it arrives and sent then.
///
/// rider-fixrev3-3: the names of those fields are stored next to the device
/// copy (under [pendingKey]) so a change the server never received (the
/// read or the PATCH failed) is still laid over the server copy and sent
/// after a restart, instead of being silently reverted.
class SyncedProfileRepository
    implements RiderProfileRepository, ServerBackedRepository {
  SyncedProfileRepository({required ApiClient api, ProfileRepository? cache})
    : _api = api,
      _cache = cache ?? ProfileRepository();

  static const path = '/api/v1/rider/profile';

  final ApiClient _api;
  final ProfileRepository _cache;
  bool _syncPending = false;

  /// True once the server copy of this rider's profile has been read.
  bool _serverKnown = false;

  /// The fields the rider changed that the server does not have yet.
  final Set<_Field> _changed = {};
  bool _pendingLoaded = false;

  /// Where the names of the fields in [_changed] are kept on the device.
  /// UserDataWipe removes it with the device copy at sign-out.
  String get pendingKey => '${_cache.storageKey}.pending';

  Future<void>? _reading;

  /// rider-fixrev3-1: bumped by [clearLocal] (sign-out). A server read
  /// started in an earlier session answers for a rider who is no longer
  /// signed in, so its answer is dropped.
  int _session = 0;

  /// True when the last saved profile has not reached the server yet.
  bool get syncPending => _syncPending;

  @override
  RiderProfileData get current => _cache.current;

  @override
  String displayName() => _cache.displayName();

  @override
  Future<void> hydrateLocal() => _hydrateCache();

  @override
  Future<void> hydrate() async {
    await _hydrateCache();
    await _readServer();
    if (_syncPending && _serverKnown) await _resync();
  }

  Future<void>? _resyncing;

  /// Sends the pending change once, however many hydrates are waiting on
  /// the same read (launch and sign-in).
  Future<void> _resync() =>
      _resyncing ??= _resyncOnce().whenComplete(() => _resyncing = null);

  Future<void> _resyncOnce() async {
    try {
      await _sync(_cache.current, rethrowRefusal: true);
    } on ApiError catch (error) {
      // rider-u150: a change the server refuses (left pending by an
      // earlier launch) would be refused again on every save. Drop it and
      // take the server copy instead.
      AppLog.warning('profile.sync_refused', extra: {'error': '$error'});
      _changed.clear();
      _syncPending = false;
      await _storePending();
      _serverKnown = false;
      await _readServer();
    }
  }

  @override
  void clearLocal() {
    _cache.clearLocal();
    _syncPending = false;
    _serverKnown = false;
    _changed.clear();
    _pendingLoaded = false;
    // A read still in flight belongs to the signed-out rider: the next
    // hydrate starts its own.
    _session++;
    _reading = null;
  }

  /// rider-u150: throws the [ApiError] when the server refuses the
  /// profile itself (400/422, e.g. a name over 80 characters). The fields
  /// this save changed then go back to what they were, so the refused
  /// value is neither shown as saved nor sent again with every later save.
  @override
  Future<RiderProfileData> save(RiderProfileData next) async {
    final before = _cache.current;
    final pendingBefore = Set<_Field>.of(_changed);
    _changed.addAll(_Field.changedBetween(before, next));
    await _cache.save(next);
    await _storePending();
    await _readServer();
    if (_serverKnown) {
      try {
        await _sync(_cache.current, rethrowRefusal: true);
      } on ApiError {
        var restored = _cache.current;
        for (final field in _changed.difference(pendingBefore)) {
          restored = field.copy(from: before, to: restored);
        }
        _changed
          ..clear()
          ..addAll(pendingBefore);
        _syncPending = _changed.isNotEmpty;
        await _cache.save(restored);
        await _storePending();
        rethrow;
      }
    } else {
      _syncPending = true;
    }
    return _cache.current;
  }

  static Map<String, dynamic> body(RiderProfileData profile) => {
    // rider-u148: a blank name is never sent over the one the server has.
    if (profile.name.trim().isNotEmpty) 'name': profile.name.trim(),
    'language': profile.language,
    'consents': {
      'rideUpdates': profile.rideUpdates,
      'emailUpdates': profile.emailUpdates,
      'promotions': profile.promotions,
    },
  };

  /// The device copy, with the fields not yet sent (from an earlier launch)
  /// marked so the server copy does not revert them.
  Future<void> _hydrateCache() async {
    await _cache.hydrate();
    if (_pendingLoaded) return;
    _pendingLoaded = true;
    try {
      final prefs = await PreferencesStore.load();
      final names = _Field.values.asNameMap();
      for (final name in prefs.getStringList(pendingKey) ?? const []) {
        final field = names[name];
        if (field != null) _changed.add(field);
      }
    } catch (error) {
      AppLog.warning('profile.pending_load_failed', extra: {'error': '$error'});
    }
    if (_changed.isNotEmpty) _syncPending = true;
  }

  Future<void> _storePending() async {
    try {
      final prefs = await PreferencesStore.load();
      if (_changed.isEmpty) {
        await prefs.remove(pendingKey);
      } else {
        await prefs.setStringList(pendingKey, [
          for (final field in _changed) field.name,
        ]);
      }
    } catch (error) {
      AppLog.warning('profile.pending_save_failed', extra: {'error': '$error'});
    }
  }

  /// Reads the server copy once per signed-in rider and makes it the cache,
  /// with the rider's not yet sent changes laid over it.
  Future<void> _readServer() {
    if (_serverKnown) return Future<void>.value();
    final pending = _reading;
    if (pending != null) return pending;
    late final Future<void> read;
    read = _fetch().whenComplete(() {
      if (identical(_reading, read)) _reading = null;
    });
    return _reading = read;
  }

  Future<void> _fetch() async {
    final session = _session;
    final Map<String, dynamic> response;
    try {
      response = await _api.get(path);
    } catch (error) {
      AppLog.warning('profile.read_failed', extra: {'error': '$error'});
      return;
    }
    if (session != _session) {
      AppLog.info('profile.read_dropped', extra: {'reason': 'signed_out'});
      return;
    }
    final server = response['profile'];
    if (server is Map) {
      final local = _cache.current;
      var merged = _fromServer(local, Map<String, dynamic>.from(server));
      for (final field in _changed) {
        // A blank name never replaces the one the server has.
        if (field == _Field.name && local.name.trim().isEmpty) continue;
        merged = field.copy(from: local, to: merged);
      }
      await _cache.save(merged);
    }
    _serverKnown = true;
  }

  static RiderProfileData _fromServer(
    RiderProfileData base,
    Map<String, dynamic> server,
  ) {
    final name = server['name'];
    final language = server['language'];
    final raw = server['consents'];
    final consents = raw is Map ? raw : const {};
    bool? flag(String key) {
      final value = consents[key];
      return value is bool ? value : null;
    }

    return base.copyWith(
      name: name is String ? name.trim() : null,
      language: language is String
          ? RiderProfileData.languageCode(language)
          : null,
      rideUpdates: flag('rideUpdates'),
      emailUpdates: flag('emailUpdates'),
      promotions: flag('promotions'),
    );
  }

  /// A network failure or a server error keeps the change to send later.
  /// With [rethrowRefusal], a refusal of the profile itself (400/422) is
  /// thrown instead: sending it again cannot succeed.
  Future<void> _sync(
    RiderProfileData profile, {
    bool rethrowRefusal = false,
  }) async {
    try {
      await _api.patch(
        path,
        body: body(profile),
        idempotencyKey: newIdempotencyKey('profile'),
      );
      _syncPending = false;
      _changed.clear();
      await _storePending();
    } on ApiError catch (error) {
      if (rethrowRefusal && _isRefusal(error)) rethrow;
      _syncPending = true;
      AppLog.warning('profile.sync_failed', extra: {'error': '$error'});
    } catch (error) {
      _syncPending = true;
      AppLog.warning('profile.sync_failed', extra: {'error': '$error'});
    }
  }

  static bool _isRefusal(ApiError error) =>
      error.statusCode == 400 || error.statusCode == 422;
}

/// The profile fields the server holds.
enum _Field {
  name,
  language,
  rideUpdates,
  emailUpdates,
  promotions;

  static Iterable<_Field> changedBetween(
    RiderProfileData a,
    RiderProfileData b,
  ) => values.where((field) => field._read(a) != field._read(b));

  Object _read(RiderProfileData profile) => switch (this) {
    name => profile.name.trim(),
    language => profile.language,
    rideUpdates => profile.rideUpdates,
    emailUpdates => profile.emailUpdates,
    promotions => profile.promotions,
  };

  RiderProfileData copy({
    required RiderProfileData from,
    required RiderProfileData to,
  }) => switch (this) {
    name => to.copyWith(name: from.name),
    language => to.copyWith(language: from.language),
    rideUpdates => to.copyWith(rideUpdates: from.rideUpdates),
    emailUpdates => to.copyWith(emailUpdates: from.emailUpdates),
    promotions => to.copyWith(promotions: from.promotions),
  };
}
