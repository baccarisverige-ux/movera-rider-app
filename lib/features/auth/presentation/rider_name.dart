import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Step 3, new riders only: the name the driver will look for. Replaces the
/// old Create account screen. Apple or Google riders arrive pre-filled.
///
/// The session already exists here, so there is no back button.
class RiderNameScreen extends StatefulWidget {
  const RiderNameScreen({
    super.key,
    this.initialName,
    this.profile,
    this.language,
  });

  final String? initialName;
  final ProfileController? profile;

  /// The language the app speaks (default: the app's own controller).
  final AppLanguageController? language;

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
      // rider-u75: the server speaks to the rider in the language the app
      // already speaks (their choice, else the zone's), not the 'en'
      // default of a fresh profile.
      final language = widget.language ?? AppScope.instance.language;
      await profile.update(
        profile.profile.copyWith(
          name: last.isEmpty ? first : '$first $last',
          language: language.code,
        ),
      );
      await PendingRiderName.clear();
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
              // rider-u78: first (40) + space + last stays within the
              // profile's 80 characters.
              maxLength: RiderProfileData.maxNameLength - 41,
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
    // Owner round 3: the same wordmark widget as every other screen.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const MoveraWordmark(size: 13),
        Flexible(
          child: Text(
            context.l10n.brandTagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AuthText.small(),
          ),
        ),
      ],
    );
  }
}
