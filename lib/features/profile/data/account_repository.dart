import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';

/// What the backend said about an account deletion request.
class AccountDeletionRequest {
  const AccountDeletionRequest({required this.status, this.eraseDueAt});

  /// `requested` (contract `accountDeletion.status`): the account is closed
  /// now. From contract v0.18.134 the server erases it 30 days after the
  /// request (a debt is kept as a record until paid); any text is accepted.
  final String status;

  /// v0.18.134: from when the server may erase it; null from an older server.
  final DateTime? eraseDueAt;
}

class AccountRepository {
  AccountRepository({ApiClient? api}) : _api = api ?? AppScope.instance.api;

  final ApiClient _api;

  /// Asks the backend to delete this rider's account (`POST
  /// /api/v1/account/deletion`, 202 `{status: "requested"}`, v0.18.134 adds
  /// `requestedAt` + `eraseDueAt`). Throws when the request was not
  /// accepted (409 `deletion_open_trip` as an ApiError), so the screen never
  /// claims it was sent.
  Future<AccountDeletionRequest> requestDeletion() async {
    final response = await _api.post('/api/v1/account/deletion');
    final status = response['status'];
    if (status is! String || status.trim().isEmpty) {
      throw StateError('Account deletion response was incomplete.');
    }
    final due = response['eraseDueAt'];
    return AccountDeletionRequest(
      status: status.trim(),
      eraseDueAt: due is String ? DateTime.tryParse(due) : null,
    );
  }
}
