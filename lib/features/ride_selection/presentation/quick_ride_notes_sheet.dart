import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

Future<RideNotes?> showQuickRideNotesSheet(
  BuildContext context, {
  RideNotes initial = RideNotes.empty,
}) {
  SheetCoordinator.instance.open(RideSheet.notes);
  return MoveraSheet.show<RideNotes>(
    context: context,
    builder: (_) => QuickRideNotesSheet(initial: initial),
  ).whenComplete(() => SheetCoordinator.instance.close(RideSheet.notes));
}

class QuickRideNotesSheet extends StatefulWidget {
  const QuickRideNotesSheet({super.key, this.initial = RideNotes.empty});

  final RideNotes initial;

  @override
  State<QuickRideNotesSheet> createState() => _QuickRideNotesSheetState();
}

class _QuickRideNotesSheetState extends State<QuickRideNotesSheet> {
  RideNotes _notes = RideNotes.empty;

  @override
  void initState() {
    super.initState();
    _notes = widget.initial;
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = MoveraTokens.ink,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  void _submit() => Navigator.pop(context, _notes);

  bool _on(String key) => switch (key) {
    'bags' => _notes.bags,
    'pet' => _notes.pet,
    'baby' => _notes.baby,
    _ => _notes.child,
  };

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final items = [
      (key: 'bags', label: context.l10n.notesBags, art: AppAssets.noteBags),
      (key: 'pet', label: context.l10n.notesPet, art: AppAssets.notePet),
      (key: 'baby', label: context.l10n.notesBaby, art: AppAssets.noteBaby),
      (key: 'child', label: context.l10n.notesChild, art: AppAssets.noteChild),
    ];
    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MoveraTokens.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.notesTitle,
              style: _text(22, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.notesBody,
              style: _text(13.5, color: const Color(0xFF5C656C)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _NoteTile(
                    label: items[0].label,
                    art: items[0].art,
                    selected: _on(items[0].key),
                    onTap: () =>
                        setState(() => _notes = _notes.toggle(items[0].key)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NoteTile(
                    label: items[1].label,
                    art: items[1].art,
                    selected: _on(items[1].key),
                    onTap: () =>
                        setState(() => _notes = _notes.toggle(items[1].key)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _NoteTile(
                    label: items[2].label,
                    art: items[2].art,
                    selected: _on(items[2].key),
                    onTap: () =>
                        setState(() => _notes = _notes.toggle(items[2].key)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NoteTile(
                    label: items[3].label,
                    art: items[3].art,
                    selected: _on(items[3].key),
                    onTap: () =>
                        setState(() => _notes = _notes.toggle(items[3].key)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.pop(context, RideNotes.empty),
                child: Text(
                  context.l10n.notesSkip,
                  style: _text(
                    14,
                    weight: FontWeight.w600,
                    color: const Color(0xFF5C656C),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: MoveraTokens.cta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  context.l10n.findDriver,
                  style: _text(
                    16,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.label,
    required this.art,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String art;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? MoveraTokens.ink : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: MoveraMotion.selection(
          selected: selected,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? MoveraTokens.ink : MoveraTokens.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      height: 72,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFF6F8FA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Image.asset(
                        art,
                        height: 64,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        cacheWidth: 192,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : MoveraTokens.ink,
                      ),
                    ),
                  ],
                ),
                if (selected)
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
