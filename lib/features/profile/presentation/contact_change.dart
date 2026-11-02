import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What [ContactChangePage] changes.
enum ContactKind { phone, email }

/// The rider's `POST` (path, body) → answer.
typedef ContactPost =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    );

/// Decision driver-g1 (owner 2026-11-02, "same flow for riders"): the rider
/// changes the phone number or e-mail in the app: the new value → a code
/// sent to it → saved (contract v0.18.14 `deepFix1.accountChange`:
/// `POST /account/phone/change` → `/account/phone/verify`,
/// `POST /account/email/change` → `/account/email/verify`).
class ContactChangePage extends StatefulWidget {
  const ContactChangePage({
    super.key,
    required this.kind,
    required this.post,
    this.onSaved,
  });

  final ContactKind kind;
  final ContactPost post;

  /// Told after the server saved it (the account is read again).
  final Future<void> Function()? onSaved;

  @override
  State<ContactChangePage> createState() => _ContactChangePageState();
}

class _ContactChangePageState extends State<ContactChangePage> {
  final _value = TextEditingController();
  final _code = TextEditingController();
  String? _challenge;
  String? _error;
  bool _busy = false;

  bool get _phone => widget.kind == ContactKind.phone;

  @override
  void dispose() {
    _value.dispose();
    _code.dispose();
    super.dispose();
  }

  String _message(Object error) {
    final l10n = context.l10n;
    if (error is ApiError) {
      switch (error.detail) {
        case 'phone_taken':
          return l10n.contactPhoneTaken;
        case 'email_taken':
          return l10n.contactEmailTaken;
        case 'invalid_otp_code' || 'invalid_otp':
          return l10n.errWrongCode;
        case 'otp_expired' || 'invalid_otp_session':
          return l10n.codeExpired;
        case 'reauth_required':
          return l10n.contactReauthRequired;
        case 'change_too_many':
          return l10n.contactChangeTooMany;
      }
    }
    if (riderErrorKind(error) == RiderErrorKind.offline) return l10n.errOffline;
    return l10n.contactChangeFailed;
  }

  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    final value = _value.text.trim();
    if (value.isEmpty) return;
    final answer = await widget.post(
      _phone ? '/api/v1/account/phone/change' : '/api/v1/account/email/change',
      _phone ? {'phone': value} : {'email': value},
    );
    final id = _phone ? answer['sessionId'] : answer['challengeId'];
    if (mounted) setState(() => _challenge = '$id');
  });

  Future<void> _verify() => _run(() async {
    final challenge = _challenge;
    final code = _code.text.trim();
    if (challenge == null || code.isEmpty) return;
    try {
      await widget.post(
        _phone
            ? '/api/v1/account/phone/verify'
            : '/api/v1/account/email/verify',
        _phone
            ? {
                'phone': _value.text.trim(),
                'sessionId': challenge,
                'code': code,
              }
            : {'challengeId': challenge, 'code': code},
      );
    } catch (_) {
      _code.clear();
      rethrow;
    }
    try {
      await widget.onSaved?.call();
    } catch (_) {
      // Saved / kept as it is: the next read shows the server's state.
    }
    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_phone ? l10n.contactPhoneSaved : l10n.contactEmailSaved),
      ),
    );
    Navigator.of(context).maybePop();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sent = _challenge != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_phone ? l10n.contactChangePhone : l10n.contactChangeEmail),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('contact-value'),
              controller: _value,
              enabled: !sent && !_busy,
              style: const TextStyle(fontSize: 16),
              keyboardType: _phone
                  ? TextInputType.phone
                  : TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: _phone ? l10n.contactNewPhone : l10n.contactNewEmail,
              ),
            ),
            if (sent) ...[
              const SizedBox(height: 12),
              Text(
                _phone ? l10n.contactCodeSentPhone : l10n.contactCodeSentEmail,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('contact-code'),
                controller: _code,
                enabled: !_busy,
                style: const TextStyle(fontSize: 16),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.contactCode),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('contact-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('contact-submit'),
              onPressed: _busy ? null : (sent ? _verify : _send),
              child: Text(sent ? l10n.contactSave : l10n.contactSendCode),
            ),
          ],
        ),
      ),
    );
  }
}
