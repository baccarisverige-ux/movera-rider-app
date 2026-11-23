import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/shared/formatters/money.dart';
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

  /// The highest fare the rider may offer (v0.18.6, owner G4-E4: the zone's
  /// `raisePrice.maxFactor` × the booked fare). A step that would go above
  /// it is not shown.
  final double maxPrice;

  /// v0.18.6 (G4-E4): the [steps] whose raise keeps a fare of
  /// [currentMinor] at or under [maxMinor], all in minor units of
  /// [currency].
  static List<int> stepsUnder(
    List<int> steps, {
    required int currentMinor,
    required int maxMinor,
    required String currency,
  }) {
    final unit = Money.minorPerMajor(currency);
    return [
      for (final step in steps)
        if (currentMinor + step * unit <= maxMinor) step,
    ];
  }

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

  /// [major] in minor units, exact in every currency: the fare is shown to
  /// the öre now (price format, owner 2026-11-14), so it counts from there.
  int _minorOf(double major) =>
      Money.fromLegacyMajor(major, widget.currency).amountMinor;

  int get _currentMinor => _minorOf(widget.currentPrice);

  /// The ceiling to the minor unit (never rounded up past the server's
  /// limit).
  int get _maxMinor =>
      Money.fromLegacyMajor(widget.maxPrice, widget.currency).amountMinor;

  /// v0.18.6 (G4-E4): only the steps that stay under the limit.
  List<int> get _steps => PriceBumpCard.stepsUnder(
    widget.steps,
    currentMinor: _currentMinor,
    maxMinor: _maxMinor,
    currency: widget.currency,
  );

  /// [amount] in the trip's currency, exact, as the fare is shown.
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
      return _currentMinor + increase > _maxMinor ? null : increase;
    }
    final extra = total * _unitMinor - _currentMinor;
    if (extra <= 0 || total * _unitMinor > _maxMinor) {
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
      _selectedStep = extraMinor % _unitMinor == 0 && _steps.contains(extra)
          ? extra
          : null;
    });
  }

  // ---- R2 slider (owner 2026-11-23): the same choice as the steps and the
  // typed price, made on a slider from the fare to the ceiling. ----

  /// The slider's ends in whole units: from the fare (a fare with cents
  /// starts at its whole unit) to the ceiling (never past it).
  double get _sliderMin => _currentMinor / _unitMinor;
  double get _sliderMax => (_maxMinor ~/ _unitMinor).toDouble() < _sliderMin
      ? _sliderMin
      : (_maxMinor ~/ _unitMinor).toDouble();

  /// The total the slider stands on, in minor units.
  int get _chosenMinor => _currentMinor + (_increase ?? 0);

  /// A drag this close to a step (in whole units) lands on it; small
  /// enough that every whole unit stays reachable.
  static const double _snap = 0.3;

  void _onSlide(double value) {
    if (widget.busy) return;
    for (final step in _steps) {
      final at = _sliderMin + step;
      if ((value - at).abs() <= _snap) {
        if (_selectedStep != step) _selectStep(step);
        return;
      }
    }
    final whole = value.round();
    if (whole * _unitMinor <= _currentMinor) {
      setState(() {
        _selectedStep = null;
        _price.text = '';
      });
      return;
    }
    _price.text = '$whole';
    _onTyped('$whole');
  }

  double get _sliderValue =>
      (_chosenMinor / _unitMinor).clamp(_sliderMin, _sliderMax).toDouble();

  String _whole(num major) {
    final text = formatMajor(major, widget.currency);
    // "313,00 kr" -> "313" (the bubble and the track show whole units).
    final number = text.split(' ').first;
    final cut = number.indexOf(RegExp(r'[,.]\d+$'));
    return cut > 0 && major == major.roundToDouble()
        ? number.substring(0, cut)
        : number;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final l10n = context.l10n;
    final range = _sliderMax - _sliderMin;
    double fraction(double total) =>
        range <= 0 ? 0 : ((total - _sliderMin) / range).clamp(0.0, 1.0);
    final chosen = _chosenMinor / _unitMinor;
    final increase = _increase;
    return Container(
      key: const ValueKey('price-bump-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MoveraTokens.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14162C36),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.raiseOfferEntry,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: MoveraTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.bumpSubtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.35,
                        color: MoveraTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: const Color(0xFFF1F5F7),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: widget.busy ? null : widget.onKeepWaiting,
                  tooltip: l10n.keepWaiting,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: MoveraTokens.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              const inset = 16.0;
              final track = box.maxWidth - 2 * inset;
              final thumbX = inset + track * fraction(chosen);
              // Labels never overlap (close steps on a small fare).
              final xs = [
                inset,
                for (final step in steps)
                  inset + track * fraction(_sliderMin + step),
                inset + track,
              ];
              var gap = 56.0;
              for (var k = 1; k < xs.length; k++) {
                final d = xs[k] - xs[k - 1];
                if (d < gap) gap = d;
              }
              final labelW = gap.clamp(24.0, 56.0);
              const bubbleW = 184.0;
              final bubbleLeft = (thumbX - bubbleW / 2).clamp(
                0.0,
                box.maxWidth - bubbleW,
              );
              Widget label(
                String text,
                double x, {
                VoidCallback? onTap,
                bool bold = false,
              }) {
                final w = labelW;
                return Positioned(
                  left: (x - w / 2).clamp(0.0, box.maxWidth - w),
                  top: 92,
                  width: w,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.busy ? null : onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                          color: bold ? AppColor.navy : MoveraTokens.muted,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 124,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: bubbleLeft,
                      top: 0,
                      child: _Bubble(
                        key: const ValueKey('price-bump-bubble'),
                        width: bubbleW,
                        price: _whole(chosen),
                        unit: _unit,
                        difference: increase == null
                            ? null
                            : '+${_whole(increase / _unitMinor)} $_unit',
                        tipX: thumbX - bubbleLeft,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 56,
                      height: 40,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 8,
                          activeTrackColor: AppColor.navy,
                          inactiveTrackColor: const Color(0xFFE8F0F6),
                          thumbShape: const _ThumbShape(),
                          overlayShape: SliderComponentShape.noOverlay,
                          trackShape: const RoundedRectSliderTrackShape(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: inset,
                          ),
                          child: Slider(
                            padding: EdgeInsets.zero,
                            min: _sliderMin,
                            max: _sliderMax,
                            value: _sliderValue,
                            onChanged: range <= 0 || widget.busy
                                ? null
                                : _onSlide,
                            semanticFormatterCallback: (v) => formatMoney(
                              Money(v.round() * _unitMinor, widget.currency),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final step in steps)
                      if (_sliderMin + step > chosen)
                        Positioned(
                          left: inset + track * fraction(_sliderMin + step) - 3,
                          top: 73,
                          child: const IgnorePointer(
                            child: SizedBox.square(
                              dimension: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFF9CC3E0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    label(_whole(widget.currentPrice), inset),
                    for (final step in steps)
                      label(
                        '+${_whole(step)}',
                        inset + track * fraction(_sliderMin + step),
                        bold: _selectedStep == step,
                        onTap: () => _selectStep(step),
                      ),
                    label(_whole(_maxMinor / _unitMinor), inset + track),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // D-012: the total is a preview; the server confirms the price
          // (said in the line; marked once a raise is chosen).
          KeyedSubtree(
            key: _canConfirm
                ? const ValueKey('price-bump-server-confirms')
                : null,
            child: Text(
              l10n.bumpSliderHint(
                formatMoney(Money(_maxMinor, widget.currency)),
              ),
              key: const ValueKey('price-bump-max'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                height: 1.35,
                color: MoveraTokens.muted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const ValueKey('price-bump-confirm'),
              onPressed: !widget.busy && _canConfirm ? _confirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111614),
                disabledBackgroundColor: MoveraTokens.line,
                shape: const StadiumBorder(),
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
                          ? l10n.bumpConfirm(
                              formatMoney(
                                Money(
                                  _currentMinor + _increase!,
                                  widget.currency,
                                ),
                              ),
                            )
                          : l10n.bumpSetNewPrice,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: _canConfirm
                            ? Colors.white
                            : const Color(0xFF9AA3A9),
                      ),
                    ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: widget.busy ? null : widget.onKeepWaiting,
              child: Text(
                l10n.keepWaiting,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: MoveraTokens.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The navy price bubble over the thumb: the new total and, once chosen,
/// the difference.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.width,
    required this.price,
    required this.unit,
    required this.difference,
    required this.tipX,
  });

  final double width;
  final String price;
  final String unit;
  final String? difference;
  final double tipX;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (tipX - 6).clamp(10.0, width - 22),
            bottom: 0,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(width: 12, height: 12, color: AppColor.navy),
            ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            decoration: BoxDecoration(
              color: AppColor.navy,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                if (difference != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        difference!,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White thumb with a navy ring and a navy centre.
class _ThumbShape extends SliderComponentShape {
  const _ThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(34);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas
      ..drawCircle(
        center.translate(0, 1),
        17,
        Paint()
          ..color = const Color(0x33061B44)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawCircle(center, 16, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        14.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColor.navy,
      )
      ..drawCircle(center, 5, Paint()..color = AppColor.navy);
  }
}

/// "Raise your offer" on the search sheet while the raise card is closed
/// (owner, live test 2026-10-26: "while search and wait long time can't add
/// money"). Opens the card again through [FindingDriverController.openPriceBump].
class RaiseOfferEntry extends StatelessWidget {
  const RaiseOfferEntry({
    super.key,
    required this.controller,
    required this.onOpened,
  });

  final FindingDriverController controller;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          key: const ValueKey('raise-offer-entry'),
          onPressed: () {
            controller.openPriceBump();
            onOpened();
          },
          icon: const Icon(Icons.trending_up_rounded, size: 20),
          label: Text(
            context.l10n.raiseOfferEntry,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: MoveraTokens.ink,
            side: const BorderSide(color: MoveraTokens.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
