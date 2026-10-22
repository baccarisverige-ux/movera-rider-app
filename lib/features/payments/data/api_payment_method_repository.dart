import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/domain/payment_repository.dart';

/// The rider's payment methods and default method on the server (ARCH-7).
///
/// PROPOSED, needs agreement with Driver, Admin and backend (C-10):
/// `GET /api/v1/payment-methods` →
/// `{code, methods: [{id, kind, label, detail?}], defaultMethodId}` and
/// `PATCH /api/v1/payment-methods/default` `{methodId}`. Saved cards are
/// PSP-tokenised methods in the same list; the app never sends card data.
class ApiPaymentMethodRepository
    implements PaymentRepository, DefaultPaymentStore, ServerBackedRepository {
  ApiPaymentMethodRepository({required ApiClient api}) : _api = api;

  static const path = '/api/v1/payment-methods';

  final ApiClient _api;
  String? _defaultId;

  /// rider-fixrev3-5: bumped by every [save]. A read that answers after a
  /// save was made keeps the saved choice instead of the server's older one.
  int _saves = 0;

  /// rider-u132: a default the rider chose that the server has not taken
  /// (the PATCH failed). It is sent again on the next read, and until the
  /// server has it the server's older default does not replace it.
  String? _unsaved;

  @override
  Future<List<PaymentMethod>> listMethods() async {
    final json = await _api.get(path);
    if (_unsaved == null) {
      _defaultId = _string(json['defaultMethodId']) ?? _defaultId;
    }
    final raw = json['methods'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) ?_method(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<void> setDefault(String methodId) => save(methodId);

  @override
  Future<String?> read() async {
    final unsaved = _unsaved;
    if (unsaved != null) await _send(unsaved);
    final saves = _saves;
    try {
      final json = await _api.get(path);
      if (saves == _saves && _unsaved == null) {
        _defaultId = _string(json['defaultMethodId']) ?? _defaultId;
      }
    } catch (error) {
      // The last known choice (or the caller's Cash fallback) stands.
      AppLog.warning(
        'payments.default_read_failed',
        extra: {'error': '$error'},
      );
    }
    return _defaultId;
  }

  @override
  Future<void> save(String brand) async {
    _defaultId = brand;
    _saves++;
    await _send(brand);
  }

  Future<void> _send(String brand) async {
    try {
      await _api.patch(
        '$path/default',
        body: {'methodId': brand},
        idempotencyKey: newIdempotencyKey('payment-default'),
      );
      // rider-r5-28: the rider's latest choice saved; an older one that
      // did not is no longer theirs to send again.
      if (_unsaved == brand || _defaultId == brand) _unsaved = null;
    } catch (error) {
      if (_defaultId == brand) _unsaved = brand;
      AppLog.warning(
        'payments.default_save_failed',
        extra: {'error': '$error'},
      );
    }
  }

  @override
  void clearLocal() {
    _defaultId = null;
    _unsaved = null;
  }

  static PaymentMethod? _method(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final label = _string(json['label']);
    final kind = switch (json['kind']) {
      'wallet' => PaymentMethodKind.wallet,
      'applePay' || 'apple_pay' => PaymentMethodKind.applePay,
      'googlePay' || 'google_pay' => PaymentMethodKind.googlePay,
      'card' => PaymentMethodKind.card,
      'cash' => PaymentMethodKind.cash,
      _ => null,
    };
    if (id == null || label == null || kind == null) return null;
    return PaymentMethod(
      id: id,
      kind: kind,
      label: label,
      detail: _string(json['detail']),
    );
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
}
