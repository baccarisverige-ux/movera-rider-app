import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner decision 7: the phone field's country sheet. Every country, its
/// flag and dial code, searchable by name (English or the app language),
/// ISO code or dial code. Null when dismissed.
Future<PhoneCountry?> showPhoneCountryPicker(
  BuildContext context, {
  required PhoneCountry selected,
}) {
  return MoveraSheet.show<PhoneCountry>(
    context: context,
    builder: (sheet) {
      final media = MediaQuery.of(sheet);
      // Tall enough to browse, and above the keyboard while searching.
      final height = math.min(
        media.size.height * 0.86,
        media.size.height - media.viewInsets.bottom - media.padding.top - 24,
      );
      return SizedBox(
        height: math.max(height, 240),
        child: PhoneCountrySheet(selected: selected),
      );
    },
  );
}

class PhoneCountrySheet extends StatefulWidget {
  const PhoneCountrySheet({super.key, required this.selected});

  final PhoneCountry selected;

  @override
  State<PhoneCountrySheet> createState() => _PhoneCountrySheetState();
}

class _PhoneCountrySheetState extends State<PhoneCountrySheet> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = context.l10n.localeName;
    final found = PhoneCountries.search(_query.text, language);
    // The current country leads the list until the rider searches.
    final countries = _query.text.trim().isEmpty
        ? [
            widget.selected,
            for (final c in found)
              if (c.iso != widget.selected.iso) c,
          ]
        : found;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AuthColors.stepIdle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Semantics(
              header: true,
              child: Text(
                context.l10n.chooseCountry,
                style: AuthText.cardTitle(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AuthColors.field,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AuthColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('phone-country-search'),
                      controller: _query,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      style: AuthText.input().copyWith(fontSize: 15),
                      cursorColor: AuthColors.ink,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: context.l10n.searchCountry,
                        hintStyle: AuthText.input().copyWith(
                          fontSize: 15,
                          color: const Color(0xFF9AA79F),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: countries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.noCountryFound,
                      textAlign: TextAlign.center,
                      style: AuthText.cardSub(),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: countries.length,
                    itemBuilder: (context, i) => _CountryRow(
                      country: countries[i],
                      name: countries[i].nameIn(language),
                      selected: countries[i].iso == widget.selected.iso,
                      onTap: () => Navigator.of(context).pop(countries[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final PhoneCountry country;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, ${country.dialLabel}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('phone-country-${country.iso}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: selected
              ? BoxDecoration(
                  color: AuthColors.noteGround,
                  borderRadius: BorderRadius.circular(14),
                )
              : null,
          child: Row(
            children: [
              Text(country.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: AuthColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                country.dialLabel,
                style: GoogleFonts.urbanist(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AuthColors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AuthColors.green,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
