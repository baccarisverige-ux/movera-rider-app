import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SafetyUi {
  static const ink = Color(0xFF1C2329);
  static const muted = Color(0xFF6F767C);
  static const accent = Color(0xFF2D5878);
  static const canvas = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const well = Color(0xFFF4F4F4);
  static const line = Color(0xFFE6E6E6);
  static const danger = Color(0xFFB42318);

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static BoxDecoration cardDecoration({double radius = 24}) {
    return BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: line),
    );
  }
}

class SafetyScaffold extends StatelessWidget {
  const SafetyScaffold({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.showTitle = true,
    this.solarBack = false,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final bool showTitle;

  /// Draws the back chevron as a Solar icon (RideCheck pages are Solar only).
  final bool solarBack;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: SafetyUi.canvas,
      canvasColor: SafetyUi.canvas,
      colorScheme: const ColorScheme.light(
        primary: SafetyUi.accent,
        surface: SafetyUi.card,
        onSurface: SafetyUi.ink,
      ),
    );
    return Theme(
      data: light,
      child: Scaffold(
        backgroundColor: SafetyUi.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: solarBack
                          ? const AppIconAsset(
                              AppAssets.solarAltArrowLeft,
                              size: 20,
                              color: SafetyUi.ink,
                            )
                          : const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: SafetyUi.ink,
                      tooltip: context.l10n.back,
                    ),
                    if (showTitle)
                      Expanded(
                        child: Text(
                          title,
                          style: SafetyUi.text(17, weight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: child),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

class SafetyMarkWell extends StatelessWidget {
  const SafetyMarkWell(this.asset, {super.key, this.size = 58});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SafetyUi.line),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: SafetyMark(asset, size: size - 8),
    );
  }
}

class SafetyRow extends StatelessWidget {
  const SafetyRow({
    super.key,
    required this.mark,
    required this.title,
    required this.subtitle,
    this.status,
    this.onTap,
    this.showDivider = true,
  });

  final String mark;
  final String title;
  final String subtitle;
  final String? status;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: onTap != null,
          // UI-7: the subtitle and status (e.g. "Unavailable") are heard too.
          label: [
            title,
            subtitle,
            if (status != null && status!.isNotEmpty) status!,
          ].where((part) => part.trim().isNotEmpty).join(', '),
          onTap: onTap,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(
                  children: [
                    SafetyMarkWell(mark),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: SafetyUi.text(
                              15.5,
                              weight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: SafetyUi.text(
                              13,
                              color: SafetyUi.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          status!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: SafetyUi.text(
                            12.5,
                            color: SafetyUi.accent,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: SafetyUi.muted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 86),
            child: Divider(height: 1, color: SafetyUi.line),
          ),
      ],
    );
  }
}

class SafetyPinCadre extends StatelessWidget {
  const SafetyPinCadre({
    super.key,
    required this.pin,
    required this.caption,
  });

  final String pin;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final digits = (pin.length >= 4 ? pin.substring(0, 4) : pin.padRight(4)).split('');
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: SafetyUi.ink.withValues(alpha: 0.16)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
        decoration: BoxDecoration(
          color: SafetyUi.card,
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: SafetyUi.ink.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            const SafetyMark(SafetyMarks.pin, size: 78),
            const SizedBox(height: 14),
            Text(
              context.l10n.yourPinCaps,
              style: SafetyUi.text(
                11,
                weight: FontWeight.w600,
                color: SafetyUi.muted,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < digits.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _PinDigit(digits[i]),
                  ],
                ],
              ),
            )),
            const SizedBox(height: 18),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: SafetyUi.text(13, color: SafetyUi.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDigit extends StatelessWidget {
  const _PinDigit(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 66,
      decoration: BoxDecoration(
        color: SafetyUi.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SafetyUi.ink.withValues(alpha: 0.12)),
      ),
      alignment: Alignment.center,
      child: Text(
        value,
        style: SafetyUi.text(28, weight: FontWeight.w500, letterSpacing: 0.4),
      ),
    );
  }
}
