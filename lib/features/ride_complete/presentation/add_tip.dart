import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';

class RideCompletedAddTip extends StatefulWidget {
  const RideCompletedAddTip({super.key, this.controller, this.onTipChanged});

  final RideCompleteController? controller;
  final ValueChanged<int?>? onTipChanged;

  @override
  State<RideCompletedAddTip> createState() => _RideCompletedAddTipState();
}

class _RideCompletedAddTipState extends State<RideCompletedAddTip> {
  late final RideCompleteController _ctl =
      widget.controller ?? AppScope.instance.rideComplete;
  /// Q5: the trip zone's tips, in its currency. The seed shows on the
  /// first frame; the zone's config replaces it once read.
  late List<Money> _amounts = _ctl.initialTips();
  late final String? _driverName = _ctl.driver()?.name;
  Money? _selected;

  @override
  void initState() {
    super.initState();
    _loadTips();
  }

  Future<void> _loadTips() async {
    final List<Money> amounts;
    try {
      amounts = await _ctl.tips();
    } catch (_) {
      return;
    }
    if (!mounted || _sameAmounts(amounts, _amounts)) return;
    setState(() {
      _amounts = amounts;
      if (_selected != null && !amounts.contains(_selected)) {
        _selected = null;
        widget.onTipChanged?.call(null);
      }
    });
  }

  static bool _sameAmounts(List<Money> a, List<Money> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  void _choose(Money amount) {
    final selected = _selected == amount ? null : amount;
    setState(() => _selected = selected);
    widget.onTipChanged?.call(selected?.amountMinor);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: TextWidget(
            text: _driverName == null
                ? 'Tip your driver'
                : 'Tip $_driverName',
            color: AppColor.title,
            fontSize: 16,
            fontWeight: fwSemiBold,
          ),
        ),
        if (_amounts.isEmpty)
          const MoveraEmptyState(
            icon: Icons.volunteer_activism_outlined,
            title: 'Tips unavailable',
            message: "Tipping isn't available in this build.",
            compact: true,
          )
        else ...[
          const SizedBox(height: 14),
          // Centre the row so chips size to their content instead of being
          // stretched full width by the completion screen's column.
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final amount in _amounts)
                  _TipChip(
                    amount: formatMoneyShort(amount),
                    selected: _selected == amount,
                    onTap: () => _choose(amount),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextWidget(
            text: _selected == null
                ? 'Tip is optional.'
                : '${formatMoneyShort(_selected!)} selected.',
            color: AppColor.subtitle,
            fontSize: 12,
            fontWeight: fwMedium,
          ),
        ],
      ],
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final String amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2D5878);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tip $amount',
      child: Material(
        color: selected ? accent : Colors.white,
        borderRadius: BorderRadius.circular(A11y.minTap / 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(A11y.minTap / 2),
          // No `alignment:` here — a Container given one and no width grows to
          // fill its constraints, which stretched every chip across the screen.
          // widthFactor/heightFactor keep Center shrink-wrapped to the label.
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 84,
              minHeight: A11y.minTap,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(A11y.minTap / 2),
              border: Border.all(
                color: selected ? accent : AppColor.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: TextWidget(
                text: amount,
                color: selected ? AppColor.whiteText : AppColor.title,
                fontSize: 15,
                fontWeight: fwSemiBold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
