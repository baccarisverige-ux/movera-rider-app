import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/logging/app_log.dart';
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
  Future<void> hydrateLocal() => _cache.hydrate();

  @override
  Future<void> hydrate() async {
    await _cache.hydrate();
    await _readServer();
    if (_syncPending && _serverKnown) await _sync(_cache.current);
  }

  @override
  void clearLocal() {
    _cache.clearLocal();
    _syncPending = false;
    _serverKnown = false;
    _changed.clear();
    // A read still in flight belongs to the signed-out rider: the next
    // hydrate starts its own.
    _session++;
    _reading = null;
  }

  @override
  Future<RiderProfileData> save(RiderProfileData next) async {
    _changed.addAll(_Field.changedBetween(_cache.current, next));
    await _cache.save(next);
    await _readServer();
    if (_serverKnown) {
      await _sync(_cache.current);
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

  Future<void> _sync(RiderProfileData profile) async {
    try {
      await _api.patch(
        path,
        body: body(profile),
        idempotencyKey: newIdempotencyKey('profile'),
      );
      _syncPending = false;
      _changed.clear();
    } catch (error) {
      _syncPending = true;
      AppLog.warning('profile.sync_failed', extra: {'error': '$error'});
    }
  }
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
