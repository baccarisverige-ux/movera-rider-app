import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/wallet/application/rider_refunds_repository.dart';
import 'package:movera_rider/features/wallet/domain/rider_refund.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

const Color _ink = Color(0xFF171C1F);
const Color _muted = Color(0xFF5C656C);
const Color _line = Color(0xFFE6E8E7);
const Color _accent = Color(0xFF356879);
const Color _danger = Color(0xFFB3261E);

TextStyle _style(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = _ink,
  double? height,
}) => GoogleFonts.poppins(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

/// BQ-V39 (contract.json#debtModel.refunds, owner Q-M4
/// decisions/session-2026-11-06.md:1102): where a refund goes. Only the
/// server's `choices` are offered (SE: wallet, Swish, bank; elsewhere:
/// wallet, bank); a card refund does not exist until a card company is
/// chosen. The amount is the server's, in its currency's decimals.
///
/// Pops with the chosen [RiderRefund] after a choice, `true` when the
/// refund turned out to be no longer waiting (re-read the list), or null
/// when the rider went back.
class RefundChoicePage extends StatefulWidget {
  const RefundChoicePage({
    super.key,
    required this.refund,
    required this.repository,
  });

  final RiderRefund refund;
  final RiderRefundsRepository repository;

  @override
  State<RefundChoicePage> createState() => _RefundChoicePageState();
}

class _RefundChoicePageState extends State<RefundChoicePage> {
  RefundChoice? _choice;
  bool _sending = false;
  bool _checked = false;
  String? _error;

  final _phone = TextEditingController();
  final _clearing = TextEditingController();
  final _account = TextEditingController();
  final _iban = TextEditingController();
  final _bic = TextEditingController();
  final _holder = TextEditingController();

  RiderRefund get _refund => widget.refund;

  @override
  void dispose() {
    for (final c in [_phone, _clearing, _account, _iban, _bic, _holder]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _digits(String raw) => raw.replaceAll(RegExp(r'[\s-]'), '');

  bool get _phoneOk =>
      RefundDestinationChoice.swishPhone.hasMatch(_phone.text.trim());
  bool get _clearingOk =>
      RefundDestinationChoice.clearingNumber.hasMatch(_digits(_clearing.text));
  bool get _accountOk =>
      RefundDestinationChoice.accountNumber.hasMatch(_digits(_account.text));
  bool get _ibanOk => RefundDestinationChoice.validIban(_iban.text);
  bool get _bicOk {
    final bic = _bic.text.trim().toUpperCase();
    return bic.isEmpty || RefundDestinationChoice.bic.hasMatch(bic);
  }

  bool get _holderOk => RefundDestinationChoice.validHolder(_holder.text);

  /// The body to send, or null while a field is not in the contract's format.
  RefundDestinationChoice? _command() {
    switch (_choice) {
      case null:
        return null;
      case RefundChoice.wallet:
        return const RefundDestinationChoice.wallet();
      case RefundChoice.swish:
        return _phoneOk
            ? RefundDestinationChoice.swish(phone: _phone.text.trim())
            : null;
      case RefundChoice.bank:
        if (_refund.swedishBank) {
          return _clearingOk && _accountOk && _holderOk
              ? RefundDestinationChoice.swedishBank(
                  clearingNumber: _digits(_clearing.text),
                  accountNumber: _digits(_account.text),
                  holderName: _holder.text.trim(),
                )
              : null;
        }
        return _ibanOk && _bicOk && _holderOk
            ? RefundDestinationChoice.iban(
                iban: _iban.text.trim(),
                bic: _bic.text.trim().toUpperCase(),
                holderName: _holder.text.trim(),
              )
            : null;
    }
  }

  void _pick(RefundChoice choice) {
    if (_sending) return;
    setState(() {
      _choice = choice;
      _checked = false;
      _error = null;
    });
  }

  Future<void> _send() async {
    final command = _command();
    if (command == null) {
      setState(() => _checked = true);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final done = await widget.repository.choose(_refund.refundId, command);
      if (!mounted) return;
      final amount = formatMoneyFull(done.amount);
      MoveraToast.show(
        context,
        done.destination == RefundChoice.wallet.wire
            ? context.l10n.refundSentToWallet(amount)
            : context.l10n.refundPayoutPending(amount),
      );
      Navigator.of(context).pop(done);
    } on ApiError catch (error) {
      if (!mounted) return;
      AppLog.warning(
        'refund.destination_failed',
        extra: {
          'code': error.code,
          'reason': error.reason ?? '',
          'status': error.statusCode ?? 0,
        },
      );
      final reason = error.reason;
      if (reason == 'destination_chosen' || error.statusCode == 409) {
        MoveraToast.show(context, context.l10n.refundAlreadyChosen);
        Navigator.of(context).pop(true);
        return;
      }
      if (reason == 'refund_not_found' || error.statusCode == 404) {
        MoveraToast.show(context, context.l10n.refundNotWaiting);
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _sending = false;
        _error = reason == 'method_not_available'
            ? context.l10n.refundChoiceUnavailable
            : reason == 'bank_details_invalid' ||
                  error.code == 'invalid_request' ||
                  error.statusCode == 400
            ? context.l10n.refundDetailsInvalid
            : context.l10n.refundSendFailed;
      });
    } catch (error) {
      if (!mounted) return;
      AppLog.warning(
        'refund.destination_failed',
        extra: {'error': '${error.runtimeType}'},
      );
      setState(() {
        _sending = false;
        _error = context.l10n.refundSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: l.back,
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            Text(
              l.refundChoiceTitle,
              style: _style(25, weight: FontWeight.w700, height: 1.2),
            ),
            const SizedBox(height: 18),
            Text(l.refundAmount, style: _style(12, color: _muted)),
            const SizedBox(height: 2),
            Text(
              formatMoneyFull(_refund.amount),
              key: const ValueKey('refund-choice-amount'),
              style: _style(30, weight: FontWeight.w700),
            ),
            if (_refund.reason.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _refund.reason.trim(),
                style: _style(12.5, weight: FontWeight.w400, color: _muted),
              ),
            ],
            const SizedBox(height: 22),
            for (final choice in _refund.choices) ...[
              _option(choice),
              if (_choice == choice) _fields(choice),
              const SizedBox(height: 10),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                key: const ValueKey('refund-choice-error'),
                style: _style(13, color: _danger),
              ),
            ],
          ],
        ),
      ),
      // Pinned under the list, so the button stays in sight while the
      // keyboard and the bank fields take the screen.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              key: const ValueKey('refund-choice-send'),
              onPressed: _choice == null || _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11181D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _error == l.refundSendFailed
                          ? l.tryAgain
                          : l.refundChoiceSend,
                      style: _style(
                        15,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(RefundChoice choice) {
    final l = context.l10n;
    final (title, detail, icon) = switch (choice) {
      RefundChoice.wallet => (
        l.moveraWallet,
        l.refundWalletBody,
        Icons.account_balance_wallet_outlined,
      ),
      RefundChoice.swish => (
        'Swish',
        l.refundChoiceSwishDetail,
        Icons.phone_iphone_rounded,
      ),
      RefundChoice.bank => (
        l.refundChoiceBank,
        l.refundChoiceBankDetail,
        Icons.account_balance_outlined,
      ),
    };
    final selected = _choice == choice;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('refund-choice-${choice.wire}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _pick(choice),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _accent : _line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: _ink, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _style(15, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: _style(12, weight: FontWeight.w400, color: _muted),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _accent : _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    required bool ok,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_sending,
        keyboardType: keyboard,
        textCapitalization: caps,
        autocorrect: false,
        onChanged: (_) {
          if (_checked || _error != null) {
            setState(() => _error = null);
          }
        },
        decoration: InputDecoration(
          labelText: label,
          errorText: _checked && !ok ? context.l10n.refundFieldInvalid : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _fields(RefundChoice choice) {
    final l = context.l10n;
    final children = switch (choice) {
      RefundChoice.wallet => const <Widget>[],
      RefundChoice.swish => [
        _field(
          'refund-swish-phone',
          _phone,
          l.refundSwishPhone,
          ok: _phoneOk,
          keyboard: TextInputType.phone,
        ),
      ],
      RefundChoice.bank when _refund.swedishBank => [
        _field(
          'refund-clearing',
          _clearing,
          l.refundClearingNumber,
          ok: _clearingOk,
          keyboard: TextInputType.number,
        ),
        _field(
          'refund-account',
          _account,
          l.refundAccountNumber,
          ok: _accountOk,
          keyboard: TextInputType.number,
        ),
        _field(
          'refund-holder',
          _holder,
          l.refundHolderName,
          ok: _holderOk,
          caps: TextCapitalization.words,
        ),
      ],
      RefundChoice.bank => [
        _field(
          'refund-iban',
          _iban,
          l.refundIban,
          ok: _ibanOk,
          caps: TextCapitalization.characters,
        ),
        _field(
          'refund-bic',
          _bic,
          l.refundBic,
          ok: _bicOk,
          caps: TextCapitalization.characters,
        ),
        _field(
          'refund-holder',
          _holder,
          l.refundHolderName,
          ok: _holderOk,
          caps: TextCapitalization.words,
        ),
      ],
    };
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// BQ-V39: the Wallet screen's "Refund waiting" card, one row per refund
/// that waits for the rider's choice (GET /rider/refunds). Nothing shows
/// when none waits or the refunds API is not served on this build.
class RefundsWaitingCard extends StatefulWidget {
  const RefundsWaitingCard({
    super.key,
    this.repository,
    this.refreshToken = 0,
    this.onChanged,
  });

  final RiderRefundsRepository? repository;

  /// A new value reads the refunds again (the Wallet's FLOW-17 token).
  final int refreshToken;

  /// Called after a choice (a wallet choice changes the balance).
  final VoidCallback? onChanged;

  @override
  State<RefundsWaitingCard> createState() => _RefundsWaitingCardState();
}

class _RefundsWaitingCardState extends State<RefundsWaitingCard> {
  late final RiderRefundsRepository _repo =
      widget.repository ?? RiderRefundsRepository();
  List<RiderRefund> _waiting = const [];
  int _reads = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RefundsWaitingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (!_repo.available) return;
    final read = ++_reads;
    try {
      final waiting = await _repo.waiting();
      if (mounted && read == _reads) setState(() => _waiting = waiting);
    } catch (error) {
      AppLog.warning(
        'refund.list_failed',
        extra: {'error': '${error.runtimeType}'},
      );
    }
  }

  Future<void> _open(RiderRefund refund) async {
    final result = await Navigator.of(context).push<Object?>(
      RightToLeftTransition(
        RefundChoicePage(refund: refund, repository: _repo),
      ),
    );
    if (result == null || !mounted) return;
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        children: [
          for (final refund in _waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFFEAF2F4),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  key: ValueKey('refund-waiting-${refund.refundId}'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _open(refund),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.currency_exchange_rounded,
                          color: _accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.refundWaitingTitle,
                                style: _style(15, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l.refundWaitingBody(
                                  formatMoneyFull(refund.amount),
                                ),
                                style: _style(
                                  12.5,
                                  weight: FontWeight.w400,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: _ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
