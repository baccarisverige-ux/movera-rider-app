import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';

/// The server (movera-contracts) answers a wrong SMS code with
/// `400 invalid_request` and `reason: invalid_otp_code`. The rider must see
/// the wrong-code message, not the generic "could not check the code".
void main() {
  test('contract reason invalid_otp_code shows the wrong-code message', () {
    final error = ApiError(
      code: 'invalid_request',
      message: 'x',
      statusCode: 400,
      reason: 'invalid_otp_code',
    );
    final wrong = authErrorMessage(
      ApiError(code: 'invalid_otp', message: 'x', statusCode: 400),
      AuthAction.verifyCode,
    );
    expect(authErrorMessage(error, AuthAction.verifyCode), wrong);
    expect(
      authErrorMessage(error, AuthAction.verifyCode),
      isNot(authErrorMessage(Exception('x'), AuthAction.verifyCode)),
    );
  });
}
