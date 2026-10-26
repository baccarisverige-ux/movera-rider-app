import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Flat offer controls for delayed search — no nested dialog chrome.
class PriceBumpCard extends StatefulWidget {
  const PriceBumpCard({
    super.key,
    required this.currentPrice,
    required this.steps,
    required this.maxPrice,
    this.currency = Money.defaultCurrency,
    this.busy = false,
    required this.onConfirm,
    this.onConfirmIncrease,
    required this.onKeepWaiting,
  });

  final double currentPrice;

  /// Quick raise steps in whole units of [currency] (the zone's
  /// `raiseSteps`, owner Q6; see [wholeSteps]).
  final List<int> steps;
  final double maxPrice;

  /// Q7: the trip's currency. Prices, steps and the typed price are whole
  /// units of it.
  final String currency;
  final bool busy;

  /// The raise in whole units of [currency], when [onConfirmIncrease] is
  /// not given.
  final ValueChanged<int> onConfirm;

  /// The raise as Money in [currency]: the typed total less the current
  /// fare, to the minor unit (a 24.60 € fare raised to 30 € is +5.40 €).
  final ValueChanged<Money>? onConfirmIncrease;
  final VoidCallback onKeepWaiting;

  /// The enabled raise steps of a zone ([steps]) as whole units of
  /// [currency]: a step in another currency is never shown, and one that is
  /// not a whole unit is left out (the price field takes whole units).
  static List<int> wholeSteps(Iterable<Money> steps, String currency) {
    final unit = Money.minorPerMajor(currency);
    return [
      for (final step in steps)
        if (step.currency == currency &&
            step.amountMinor > 0 &&
            step.amountMinor % unit == 0)
          step.amountMinor ~/ unit,
    ];
  }

  /// Q6: the raise steps to offer on a trip in [currency]: the enabled
  /// `raiseSteps` of the zone's [config] when it is in [currency], else
  /// the built-in seed's (until the config is read).
  static List<int> stepsFor(RiderAppConfig? config, String currency) {
    final source = config?.currency == currency
        ? config
        : seedConfigForTrip(currency);
    return wholeSteps(source?.enabledRaiseSteps ?? const <Money>[], currency);
  }

  @override
  State<PriceBumpCard> createState() => _PriceBumpCardState();
}

class _PriceBumpCardState extends State<PriceBumpCard> {
  final _price = TextEditingController();
  final _focus = FocusNode();
  int? _selectedStep;

  int get _current => widget.currentPrice.round();

  int get _unitMinor => Money.minorPerMajor(widget.currency);

  bool get _kronor => widget.currency == Money.defaultCurrency;

  /// [major] in minor units. A kronor fare counts from the whole krona
  /// shown, as before; euros and dinars to the minor unit.
  int _minorOf(double major) => _kronor
      ? major.round() * _unitMinor
      : Money.fromLegacyMajor(major, widget.currency).amountMinor;

  int get _currentMinor => _minorOf(widget.currentPrice);

  int get _maxMinor => _minorOf(widget.maxPrice);

  /// A step that keeps the fare within its ceiling.
  bool _stepFits(int step) => _currentMinor + step * _unitMinor <= _maxMinor;

  /// Owner, live test 2026-10-26 (+200 kr): a total above the ceiling left
  /// Confirm grey with no reason; the card now says the most it can be.
  bool get _overMax {
    final total = _typedTotal;
    if (total != null) return total * _unitMinor > _maxMinor;
    final step = _selectedStep;
    return step != null && !_stepFits(step);
  }

  /// [amount] whole units of the trip's currency, as the fare is shown.
  String _money(num amount) => formatMajor(amount, widget.currency);

  /// The symbol after the typed price: "kr", "€", "DT".
  String get _unit => _money(0).split(' ').last;

  int? get _typedTotal {
    final raw = _price.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// The raise in minor units of the trip's currency.
  int? get _increase {
    final total = _typedTotal;
    final step = _selectedStep;
    if (total == null) {
      if (step == null) return null;
      final increase = step * _unitMinor;
      return _currentMinor + increase > _minorOf(widget.maxPrice)
          ? null
          : increase;
    }
    final extra = total * _unitMinor - _currentMinor;
    if (extra <= 0 || total * _unitMinor > _minorOf(widget.maxPrice)) {
      return null;
    }
    return extra;
  }

  bool get _canConfirm =>
      _increase != null &&
      _increase! > 0 &&
      (widget.onConfirmIncrease != null || _increase! % _unitMinor == 0);

  void _confirm() {
    final increase = _increase!;
    final callback = widget.onConfirmIncrease;
    if (callback != null) {
      callback(Money(increase, widget.currency));
    } else {
      widget.onConfirm(increase ~/ _unitMinor);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _selectStep(int step) {
    setState(() {
      _selectedStep = step;
      // A fare with cents (24,60 €) raised by a whole step is 26,60 €. The
      // field takes whole units only (rider-r5-13: '26.60' turned into
      // '266' on the next keystroke), so it is left empty and the step is
      // the raise; the Confirm label shows the exact total.
      _price.text = _currentMinor % _unitMinor == 0 ? '${_current + step}' : '';
      _price.selection = TextSelection.collapsed(offset: _price.text.length);
    });
  }

  void _onTyped(String value) {
    final total = int.tryParse(value.trim());
    setState(() {
      if (total == null) {
        _selectedStep = null;
        return;
      }
      // rider-r4-17: the step the typed total really raises by, to the
      // minor unit (27 on a 24,60 € fare is +2,40 €, no step).
      final extraMinor = total * _unitMinor - _currentMinor;
      final extra = extraMinor ~/ _unitMinor;
      _selectedStep =
          extraMinor % _unitMinor == 0 && widget.steps.contains(extra)
              ? extra
              : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.offer,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: MoveraTokens.muted,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: widget.busy ? null : widget.onKeepWaiting,
              tooltip: context.l10n.keepWaiting,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(
                Icons.close_rounded,
                size: 20,
                color: MoveraTokens.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.bumpTitle,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MoveraTokens.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.bumpBody,
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.35,
            color: const Color(0xFF5C656C),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10n.bumpCurrent(_money(widget.currentPrice)),
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF5C656C),
          ),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < widget.steps.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (
                var i = row;
                i < row + 2 && i < widget.steps.length;
                i++
              ) ...[
                if (i > row) const SizedBox(width: 8),
                Expanded(
                  child: _Step(
                    label: '+${formatMoneyShort(Money.fromLegacyMajor(widget.steps[i], widget.currency))}',
                    selected: _selectedStep == widget.steps[i],
                    onTap: widget.busy || !_stepFits(widget.steps[i])
                        ? null
                        : () => _selectStep(widget.steps[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Text(
          context.l10n.bumpOrSetNew,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: MoveraTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: !widget.busy,
          controller: _price,
          focusNode: _focus,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onTyped,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: MoveraTokens.ink,
          ),
          decoration: InputDecoration(
            hintText: '$_current',
            hintStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              // UI-6: was 0xFF9AA3A9 (2.41:1 on the 0xFFF6F8FA fill).
              color: MoveraTokens.subtleOnFill,
            ),
            suffixText: _unit,
            suffixStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF5C656C),
            ),
            filled: true,
            fillColor: const Color(0xFFF6F8FA),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MoveraTokens.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MoveraTokens.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MoveraTokens.accent),
            ),
          ),
        ),
        if (_overMax) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.bumpMaxPrice(
              formatMoney(Money(_maxMinor, widget.currency), whole: true),
            ),
            key: const ValueKey('price-bump-max'),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFB42318),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: !widget.busy && _canConfirm ? _confirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: MoveraTokens.cta,
              disabledBackgroundColor: MoveraTokens.line,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: widget.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _canConfirm
                        ? context.l10n.bumpConfirm(formatMoney(Money(_currentMinor + _increase!, widget.currency), whole: true))
                        : context.l10n.bumpSetNewPrice,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _canConfirm
                          ? Colors.white
                          : const Color(0xFF9AA3A9),
                    ),
                  ),
          ),
        ),
        if (_canConfirm) ...[
          const SizedBox(height: 6),
          // D-012: the total above is a preview. Only the rider's increase is
          // sent; the fare shown afterwards is the one the server returns.
          Text(
            context.l10n.bumpServerConfirms,
            key: const ValueKey('price-bump-server-confirms'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.3,
              color: MoveraTokens.muted,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: widget.busy ? null : widget.onKeepWaiting,
            child: Text(
              context.l10n.keepWaiting,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MoveraMotion.selection(
      selected: selected,
      child: Material(
        // A step above the ceiling is off: greyed fill and border too, not
        // only lighter text (owner screenshots, 2026-10-26).
        color: selected
            ? MoveraTokens.ink
            : onTap == null
            ? const Color(0xFFF1F3F5)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? MoveraTokens.ink
                    : onTap == null
                    ? const Color(0xFFF1F3F5)
                    : MoveraTokens.line,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : onTap == null
                    ? MoveraTokens.subtleOnFill
                    : MoveraTokens.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
