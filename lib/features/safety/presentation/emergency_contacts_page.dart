import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/phone_e164.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/shared/design_system/movera_confirm_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/l10n/l10n.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key, required this.controller});
  final SafetyController controller;

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  SafetyController get _ctl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _edit([EmergencyContact? existing]) async {
    await MoveraSheet.show<void>(
      context: context,
      builder: (context) =>
          _ContactEditor(controller: _ctl, existing: existing),
    );
  }

  /// FLOW-15: asks before deleting and says so when it fails.
  Future<void> _delete(EmergencyContact contact) async {
    final confirmed = await confirmMoveraAction(
      context,
      title: context.l10n.contactDeleteQ(contact.name),
      message: context.l10n.contactDeleteBody,
      confirmLabel: context.l10n.contactDeleteConfirm,
    );
    if (!confirmed || !mounted) return;
    try {
      await _ctl.removeContact(contact.id);
    } catch (_) {
      if (mounted) {
        MoveraToast.show(context, context.l10n.contactDeleteFailedRetry);
      }
    }
  }

  Future<void> _makePrimary(EmergencyContact contact) async {
    try {
      await _ctl.makePrimary(contact.id);
    } catch (_) {
      if (mounted) {
        MoveraToast.show(
          context,
          context.l10n.contactPrimaryFailed(contact.name),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _ctl.contacts;
    return SafetyScaffold(
      title: context.l10n.safetyContactsTitle,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: items.length >= kMaxEmergencyContacts
                ? null
                : () => _edit(),
            style: ElevatedButton.styleFrom(
              backgroundColor: SafetyUi.ink,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD8DEE3),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              items.length >= kMaxEmergencyContacts
                  ? context.l10n.contactsMax
                  : context.l10n.contactAdd,
              style: SafetyUi.text(
                15.5,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        children: [
          const Center(child: SafetyMark(SafetyMarks.contacts, size: 96)),
          const SizedBox(height: 16),
          Text(
            context.l10n.contactsIntro,
            textAlign: TextAlign.center,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          if (items.isEmpty)
            MoveraEmptyState(
              icon: Icons.group_outlined,
              title: context.l10n.contactsEmptyTitle,
              message: context.l10n.contactsEmptyBody,
              compact: true,
            )
          else
            Container(
              decoration: SafetyUi.cardDecoration(),
              // The rows' ink needs a Material above the card's colour.
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _ContactTile(
                        contact: items[i],
                        showDivider: i != items.length - 1,
                        onEdit: () => _edit(items[i]),
                        onDelete: () => _delete(items[i]),
                        onPrimary: () => _makePrimary(items[i]),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.showDivider,
    required this.onEdit,
    required this.onDelete,
    required this.onPrimary,
  });

  final EmergencyContact contact;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          title: Text(
            contact.name,
            style: SafetyUi.text(16, weight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                SwedishPhone.display(contact.phoneE164),
                relationshipLabel(contact.relationship),
                if (contact.isPrimary) context.l10n.contactPrimary,
                if (contact.shareTrips) context.l10n.contactTripSharing,
              ].join(' · '),
              style: SafetyUi.text(12.5, color: SafetyUi.muted),
            ),
          ),
          onTap: onEdit,
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'primary') onPrimary();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(context.l10n.edit)),
              if (!contact.isPrimary)
                PopupMenuItem(
                  value: 'primary',
                  child: Text(context.l10n.contactMakePrimary),
                ),
              PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
            ],
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 18),
            child: Divider(height: 1, color: SafetyUi.line),
          ),
      ],
    );
  }
}

class _ContactEditor extends StatefulWidget {
  const _ContactEditor({required this.controller, this.existing});
  final SafetyController controller;
  final EmergencyContact? existing;

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _relationship;
  late bool _share;
  late bool _enabled;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _phone = TextEditingController(text: existing?.phoneE164 ?? '');
    _relationship = existing?.relationship ?? 'Family';
    _share = existing?.shareTrips ?? false;
    _enabled = existing?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.controller.addContact(
          name: _name.text,
          phone: _phone.text,
          relationship: _relationship,
          shareTrips: _share,
        );
      } else {
        await widget.controller.editContact(
          widget.existing!.copyWith(
            name: _name.text,
            phoneE164: _phone.text,
            relationship: _relationship,
            shareTrips: _share,
            isEnabled: _enabled,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      // rider-84: the rider may have swiped the sheet away meanwhile.
      if (!mounted) return;
      setState(() {
        _error = widget.controller.error ?? context.l10n.contactSaveFailed;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // rider-u210: MoveraSheet already lifts the sheet above the keyboard.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SafetyUi.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.existing == null
                  ? context.l10n.contactAdd
                  : context.l10n.contactEdit,
              style: SafetyUi.text(20, weight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: context.l10n.contactName),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: context.l10n.contactPhone),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _relationship,
              decoration: InputDecoration(
                labelText: context.l10n.contactRelationship,
              ),
              items: [
                for (final label in kEmergencyContactRelationships)
                  DropdownMenuItem(
                    value: label,
                    child: Text(relationshipLabel(label)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _relationship = value);
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.contactShareTrips,
                style: SafetyUi.text(14.5),
              ),
              value: _share,
              activeThumbColor: adaptiveSwitchThumbColor(
                context,
                SafetyUi.accent,
              ),
              activeTrackColor: adaptiveSwitchTrackColor(
                context,
                SafetyUi.accent,
              ),
              onChanged: (value) => setState(() => _share = value),
            ),
            if (widget.existing != null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  context.l10n.contactEnabled,
                  style: SafetyUi.text(14.5),
                ),
                value: _enabled,
                activeThumbColor: adaptiveSwitchThumbColor(
                  context,
                  SafetyUi.accent,
                ),
                activeTrackColor: adaptiveSwitchTrackColor(
                  context,
                  SafetyUi.accent,
                ),
                onChanged: (value) => setState(() => _enabled = value),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: SafetyUi.text(13, color: SafetyUi.danger),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafetyUi.ink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _saving ? context.l10n.saving : context.l10n.save,
                  style: SafetyUi.text(
                    15.5,
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

/// A stored relationship (kept in English, as the server has it) in the app
/// language. Anything else is shown as it was typed.
String relationshipLabel(String value) => switch (value) {
  'Partner' => L10n.current.relationshipPartner,
  'Family' => L10n.current.relationshipFamily,
  'Friend' => L10n.current.relationshipFriend,
  'Colleague' => L10n.current.relationshipColleague,
  'Other' => L10n.current.relationshipOther,
  _ => value,
};
