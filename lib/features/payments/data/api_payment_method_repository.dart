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
      _defaultId = _defaultOf(json) ?? _defaultId;
    }
    // Contract `SavedPaymentMethodPage {items}`; `methods` is the older key.
    final raw = json['items'] ?? json['methods'];
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
        _defaultId = _defaultOf(json) ?? _defaultId;
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
      if (_api.contractWire) {
        // Contract `POST /payment-methods/default` `{method, paymentMethodId?}`.
        await _api.post(
          '$path/default',
          body: {
            'method': _contractMethod(brand),
            if (brand.startsWith('card:')) 'paymentMethodId': brand.substring(5),
          },
          idempotencyKey: newIdempotencyKey('payment-default'),
        );
      } else {
        await _api.patch(
          '$path/default',
          body: {'methodId': brand},
          idempotencyKey: newIdempotencyKey('payment-default'),
        );
      }
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

  /// The default method: `defaultMethodId`, else the contract item that
  /// says `isDefault`.
  static String? _defaultOf(Map<String, dynamic> json) {
    final named = _string(json['defaultMethodId']);
    if (named != null) return named;
    final items = json['items'];
    if (items is! List) return null;
    for (final item in items) {
      if (item is Map && item['isDefault'] == true) {
        return _string(item['paymentMethodId']) ?? _string(item['method']);
      }
    }
    return null;
  }

  static String _contractMethod(String brand) => switch (brand) {
    'apple' => 'apple_pay',
    'google' => 'google_pay',
    'cards' => 'card',
    _ when brand.startsWith('card:') => 'card',
    _ => brand,
  };

  static PaymentMethod? _method(Map<String, dynamic> json) {
    // Contract `SavedPaymentMethod`: `paymentMethodId` + `method`, no label.
    final id = _string(json['id']) ?? _string(json['paymentMethodId']);
    final kindRaw = json['kind'] ?? json['method'];
    final label = _string(json['label']) ?? _labelOf(kindRaw);
    final kind = switch (kindRaw) {
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

  static String? _labelOf(Object? method) => switch (method) {
    'cash' => 'Cash',
    'card' => 'Card',
    'apple_pay' => 'Apple Pay',
    'google_pay' => 'Google Pay',
    'wallet' => 'Movera Wallet',
    _ => null,
  };

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
}
