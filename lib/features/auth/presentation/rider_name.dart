import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Step 3, new riders only: the name the driver will look for. Replaces the
/// old Create account screen. Apple or Google riders arrive pre-filled.
///
/// The session already exists here, so there is no back button.
class RiderNameScreen extends StatefulWidget {
  const RiderNameScreen({super.key, this.initialName, this.profile});

  final String? initialName;
  final ProfileController? profile;

  @override
  State<RiderNameScreen> createState() => _RiderNameScreenState();
}

class _RiderNameScreenState extends State<RiderNameScreen> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final parts = (widget.initialName ?? '').trim().split(RegExp(r'\s+'));
    _first = TextEditingController(text: parts.isEmpty ? '' : parts.first);
    _last = TextEditingController(
      text: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
    _first.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _firstFocus.dispose();
    _lastFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty) {
      setState(() => _error = context.l10n.enterFirstName);
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = widget.profile ?? AppScope.instance.profile;
      await profile.hydrate();
      await profile.update(
        profile.profile.copyWith(name: last.isEmpty ? first : '$first $last'),
      );
      if (!mounted) return;
      enterMoveraApp(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.nameSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      step: 3,
      headline: context.l10n.whatCallHead,
      headlineAccent: context.l10n.whatCallAccent,
      lede: Text(context.l10n.soDriverKnows),
      showCar: false,
      card: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.firstName, style: AuthText.label()),
            const SizedBox(height: 7),
            AuthTextField(
              controller: _first,
              focusNode: _firstFocus,
              hint: context.l10n.firstName,
              autofillHints: const [AutofillHints.givenName],
              onSubmitted: (_) => _lastFocus.requestFocus(),
            ),
            if (_error != null) AuthErrorText(_error!),
            const SizedBox(height: 14),
            Text(context.l10n.lastName, style: AuthText.label()),
            const SizedBox(height: 7),
            AuthTextField(
              controller: _last,
              focusNode: _lastFocus,
              hint: context.l10n.lastName,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.familyName],
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            AuthPrimaryButton(
              label: context.l10n.letsRide,
              busy: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: 14),
            const _Signature(),
          ],
        ),
      ),
    );
  }
}

/// "Movera · Moving to a new era" under the last button.
class _Signature extends StatelessWidget {
  const _Signature();

  @override
  Widget build(BuildContext context) {
    final brand = GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Mov', style: brand.copyWith(color: AuthColors.ink)),
          TextSpan(text: 'era', style: brand.copyWith(color: AuthColors.green)),
          TextSpan(text: context.l10n.brandTagline),
        ],
      ),
      textAlign: TextAlign.center,
      style: AuthText.small(),
    );
  }
}
