import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// "Add card" (demo). The form validates the number (Visa / Mastercard,
/// Luhn), expiry, CVC and name, then saves a reference (brand, last four,
/// expiry, name) on this device. The full number and CVC are never stored.
/// When the payment partner is connected this form is replaced by its
/// secure card element.
class AddCardPage extends StatefulWidget {
  const AddCardPage({super.key, this.cards, this.now});

  /// Defaults to the app's saved cards.
  final SavedCardsController? cards;

  /// For tests: "today" when checking the expiry.
  final DateTime? now;

  static const String demoNote =
      'Demo: this card is stored on this device only. When the payment '
      'partner is connected, cards are saved in its secure vault and Movera '
      'never sees the full number.';

  /// Opens Add card; resolves with the saved card, or null when closed.
  static Future<SavedCard?> open(
    BuildContext context, {
    SavedCardsController? cards,
  }) => Navigator.of(context).push(
    MaterialPageRoute<SavedCard>(
      builder: (_) => AddCardPage(cards: cards),
    ),
  );

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _cta = Color(0xFF11181D);
  static const Color _field = Color(0xFFF6F7F7);
  static const Color _line = Color(0xFFE7EBEE);
  static const Color _error = Color(0xFFB3261E);

  @override
  State<AddCardPage> createState() => _AddCardPageState();
}

class _AddCardPageState extends State<AddCardPage> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  final _holder = TextEditingController();
  final _numberFocus = FocusNode();
  final _expiryFocus = FocusNode();
  final _cvcFocus = FocusNode();
  final _holderFocus = FocusNode();
  bool _saving = false;
  String? _saveError;

  static const Color _ink = AddCardPage._ink;
  static const Color _muted = AddCardPage._muted;
  static const Color _accent = AddCardPage._accent;
  static const Color _cta = AddCardPage._cta;
  static const Color _field = AddCardPage._field;
  static const Color _line = AddCardPage._line;
  static const Color _error = AddCardPage._error;

  SavedCardsController get _cards =>
      widget.cards ?? AppScope.instance.savedCards;

  @override
  void initState() {
    super.initState();
    for (final c in [_number, _expiry, _cvc, _holder]) {
      c.addListener(_changed);
    }
    for (final f in [_numberFocus, _expiryFocus, _cvcFocus, _holderFocus]) {
      f.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _expiry, _cvc, _holder]) {
      c.dispose();
    }
    for (final f in [_numberFocus, _expiryFocus, _cvcFocus, _holderFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _saveError = null);
  }

  TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = _ink}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c);

  // ---- validation -------------------------------------------------------

  String get _digits => CardInput.digitsOnly(_number.text);
  String? get _brand => CardInput.detectBrand(_digits);
  ({int month, int year})? get _parsedExpiry =>
      CardInput.parseExpiry(_expiry.text);

  bool get _numberOk => CardInput.numberValid(_digits);

  bool get _expiryOk {
    final e = _parsedExpiry;
    return e != null &&
        CardInput.expiryInFuture(e.month, e.year, now: widget.now);
  }

  bool get _cvcOk => CardInput.cvcValid(_cvc.text);
  bool get _holderOk => CardInput.holderValid(_holder.text);
  bool get _valid => _numberOk && _expiryOk && _cvcOk && _holderOk;

  /// Shown under the number once the rider has typed enough to be wrong.
  String? get _numberError {
    final digits = _digits;
    if (CardInput.brandRejected(digits)) return CardInput.brandError;
    final done = digits.length == 16 || (!_numberFocus.hasFocus && digits.isNotEmpty);
    if (done && !_numberOk) return context.l10n.cardCheckNumber;
    return null;
  }

  String? get _expiryError {
    final raw = CardInput.digitsOnly(_expiry.text);
    if (raw.isEmpty) return null;
    final complete = raw.length == 4 || !_expiryFocus.hasFocus;
    if (!complete) return null;
    final e = _parsedExpiry;
    if (e == null) return context.l10n.cardUseMmYy;
    if (!CardInput.expiryInFuture(e.month, e.year, now: widget.now)) {
      return context.l10n.cardExpired;
    }
    return null;
  }

  String? get _cvcError {
    if (_cvc.text.isEmpty || _cvcFocus.hasFocus) return null;
    return _cvcOk ? null : context.l10n.cardCvc3;
  }

  // ---- save -------------------------------------------------------------

  Future<void> _save() async {
    if (!_valid || _saving) return;
    final expiry = _parsedExpiry!;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final card = await _cards.add(
        number: _digits,
        expMonth: expiry.month,
        expYear: expiry.year,
        holder: _holder.text,
        now: widget.now,
      );
      if (!mounted) return;
      navigator.pop(card);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message?.toString() ?? context.l10n.cardCheckDetails;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = context.l10n.cardSaveFailed;
      });
    }
  }

  // ---- widgets ----------------------------------------------------------

  Widget _input({
    required Key key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focus,
    FocusNode? next,
    TextInputType keyboard = TextInputType.number,
    List<TextInputFormatter> formatters = const [],
    TextCapitalization capitalization = TextCapitalization.none,
    String? error,
    Widget? trailing,
    bool obscure = false,
  }) {
    final hasError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
          decoration: BoxDecoration(
            color: _field,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? _error
                  : focus.hasFocus
                  ? _ink
                  : _line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _t(11, c: _muted)),
                    TextField(
                      key: key,
                      controller: controller,
                      focusNode: focus,
                      keyboardType: keyboard,
                      inputFormatters: formatters,
                      textCapitalization: capitalization,
                      obscureText: obscure,
                      textInputAction: next == null
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) => next == null
                          ? _save()
                          : FocusScope.of(context).requestFocus(next),
                      style: _t(16, w: FontWeight.w500),
                      cursorColor: _ink,
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                        hintText: hint,
                        hintStyle: _t(
                          16,
                          w: FontWeight.w400,
                          c: const Color(0xFF9AA2A8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 0, 0),
            child: Text(error, style: _t(11.5, c: _error)),
          ),
      ],
    );
  }

  Widget _brandChip(String? brand) {
    if (brand == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Container(
        width: 40,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        child: Image.asset(
          excludeFromSemantics: true,
          brand == 'mastercard' ? AppAssets.mastercard : AppAssets.visa,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// The card at the top follows what the rider types.
  Widget _preview() {
    final digits = _digits;
    final shown = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) shown.write('  ');
      shown.write(i < digits.length ? digits[i] : '•');
    }
    final holder = _holder.text.trim();
    final expiryDigits = CardInput.digitsOnly(_expiry.text);
    final expiry = expiryDigits.length <= 2
        ? '${expiryDigits.padRight(2, 'M')}/YY'
        : '${expiryDigits.substring(0, 2)}/'
              '${expiryDigits.substring(2).padRight(2, 'Y')}';
    final brand = _brand ?? 'visa';
    return Container(
      key: const ValueKey('add-card-preview'),
      height: 190,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: brand == 'mastercard'
              ? const [Color(0xFF2B2F36), Color(0xFF11181D)]
              : const [_accent, Color(0xFF1A3449)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE9D8A6), Color(0xFFC8A85C)],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          const Spacer(),
          Text(
            shown.toString(),
            maxLines: 1,
            style: _t(19, c: Colors.white).copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  holder.isEmpty ? context.l10n.cardNameOnCardUpper : holder.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(11, c: Colors.white70),
                ),
              ),
              Text(expiry, style: _t(11, c: Colors.white70)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Image.asset(
                  excludeFromSemantics: true,
                  brand == 'mastercard' ? AppAssets.mastercard : AppAssets.visa,
                  height: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: _ink,
        title: Text(context.l10n.addCard, style: _t(18, w: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _preview(),
            const SizedBox(height: 22),
            _input(
              key: const ValueKey('add-card-number'),
              label: context.l10n.cardNumber,
              hint: '1234 5678 9012 3456',
              controller: _number,
              focus: _numberFocus,
              next: _expiryFocus,
              formatters: const [_CardNumberFormatter()],
              error: _numberError,
              trailing: _brandChip(_brand),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _input(
                    key: const ValueKey('add-card-expiry'),
                    label: context.l10n.cardExpiry,
                    hint: context.l10n.cardMmYy,
                    controller: _expiry,
                    focus: _expiryFocus,
                    next: _cvcFocus,
                    formatters: const [_ExpiryFormatter()],
                    error: _expiryError,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _input(
                    key: const ValueKey('add-card-cvc'),
                    label: 'CVC',
                    hint: '123',
                    controller: _cvc,
                    focus: _cvcFocus,
                    next: _holderFocus,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    error: _cvcError,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _input(
              key: const ValueKey('add-card-holder'),
              label: context.l10n.cardNameOnCard,
              hint: context.l10n.yourName,
              controller: _holder,
              focus: _holderFocus,
              keyboard: TextInputType.name,
              capitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline_rounded, color: _accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.l10n.addCardDemoNote, style: _t(12.5, c: _accent)),
                  ),
                ],
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Text(_saveError!, style: _t(12.5, c: _error)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const ValueKey('add-card-save'),
                onPressed: _valid && !_saving ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _cta,
                  disabledBackgroundColor: const Color(0xFFD5DADD),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        context.l10n.saveCard,
                        style: _t(16, w: FontWeight.w600, c: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Digits only, max 16, spaced in groups of four.
class _CardNumberFormatter extends TextInputFormatter {
  const _CardNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = CardInput.digitsOnly(newValue.text);
    if (digits.length > 16) digits = digits.substring(0, 16);
    final text = CardInput.groupDigits(digits);
    // Keep the caret after the same digit it followed before.
    final before = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBefore = CardInput.digitsOnly(
      newValue.text.substring(0, before),
    ).length.clamp(0, digits.length);
    final caret = digitsBefore + (digitsBefore > 0 ? (digitsBefore - 1) ~/ 4 : 0);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
  }
}

/// "MMYY" typed as digits shows as "MM/YY".
class _ExpiryFormatter extends TextInputFormatter {
  const _ExpiryFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = CardInput.digitsOnly(newValue.text);
    if (digits.length > 4) digits = digits.substring(0, 4);
    final deleting = newValue.text.length < oldValue.text.length;
    final text = digits.length > 2 || (digits.length == 2 && !deleting)
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
