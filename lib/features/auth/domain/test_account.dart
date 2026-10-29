/// Contract v0.15.0 (owner 2026-10-29, decision 6): one test number and its
/// rider account's status (`test` before the first sign-in, else the
/// account status: `active` or `suspended`).
class TestAccount {
  const TestAccount({required this.phone, required this.status, this.name});

  final String phone;
  final String status;
  final String? name;
}
