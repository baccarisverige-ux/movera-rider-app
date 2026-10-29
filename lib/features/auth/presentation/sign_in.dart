import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/application/phone_country_default.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/domain/test_account.dart';
import 'package:movera_rider/features/auth/presentation/add_phone.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/balloon_brand_intro.dart';
import 'package:movera_rider/features/auth/presentation/widgets/slow_server_note.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Step 1 for everyone: one phone field for new and returning riders, with
/// Apple and Google underneath.
class SignIn extends StatefulWidget {
  const SignIn({super.key, this.controller, this.showTestAccounts});

  final AuthController? controller;

  /// Owner 2026-10-29, decision 6 ("Only in test builds"): the test
  /// numbers with their account status under the form. Null: only a
  /// staging build (a live server that is not production).
  final bool? showTestAccounts;

  @override
  State<SignIn> createState() => _SignInState();
}

enum _Busy { phone, apple, google }

class _SignInState extends State<SignIn> with SingleTickerProviderStateMixin {
  late final AnimationController _story = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  bool _storyStarted = false;
  final _sceneKey = GlobalKey();
  final _wordmarkKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_storyStarted) {
      _storyStarted = true;
      if (MediaQuery.of(context).disableAnimations) {
        _story.value = 1;
      } else {
        _story.forward();
      }
    }
  }

  late final AuthController _auth;
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();

  /// Owner decision 7: the device's region at first, then the country of
  /// the app's saved location or zone, until the rider picks one.
  PhoneCountry _country = initialPhoneCountry();
  bool _countryPicked = false;

  Future<void> _loadDefaultCountry() async {
    final country = await defaultPhoneCountry();
    if (!mounted || _countryPicked) return;
    setState(() => _country = country);
  }

  void _pickCountry(PhoneCountry country) {
    setState(() {
      _countryPicked = true;
      _country = country;
      _phoneError = null;
    });
  }

  /// FLOW-16: the consent line names the Terms and the Privacy Policy, so
  /// both open them.
  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => _openLegal('terms');
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => _openLegal('privacy');

  void _openLegal(String kind) {
    Navigator.of(
      context,
    ).push(RightToLeftTransition(AccountLegalPage(kind: kind)));
  }

  _Busy? _busy;
  String? _phoneError;

  /// Owner decision 5: the number answered `sign_in_restricted`.
  String? _restrictedNumber;
  bool _waitlistBusy = false;
  bool _waitlistSaved = false;

  /// Owner decision 6: the test numbers (test builds only).
  List<TestAccount> _testAccounts = const [];

  /// Owner round 3: the terms box must be ticked before any sign-in path.
  bool _agreed = false;
  bool _consentNudge = false;
  String? _providerError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaultCountry());
    _auth = widget.controller ?? AppScope.instance.auth;
    _phone.addListener(_clearPhoneError);
    unawaited(_loadTestAccounts());
  }

  Future<void> _loadTestAccounts() async {
    final env = AppEnv.current;
    final show =
        widget.showTestAccounts ??
        (!env.isProduction && !env.allowsMockTransport);
    if (!show) return;
    try {
      final accounts = await _auth.testAccounts();
      if (mounted) setState(() => _testAccounts = accounts);
    } catch (_) {
      // A production server has no such list (404); nothing to show.
    }
  }

  void _useTestNumber(String e164) {
    final digits = e164.replaceAll('+', '');
    final country = PhoneCountries.ofInternational(digits) ?? _country;
    setState(() {
      _country = country;
      _countryPicked = true;
    });
    _phone.text = digits.substring(country.dial.length);
  }

  Future<void> _joinWaitlist() async {
    final number = _restrictedNumber;
    if (number == null || _waitlistBusy) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() => _waitlistBusy = true);
    try {
      await _auth.joinWaitlist(phone: number, locale: locale);
      if (mounted) setState(() => _waitlistSaved = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _phoneError = authErrorMessage(error, AuthAction.sendCode),
        );
      }
    } finally {
      if (mounted) setState(() => _waitlistBusy = false);
    }
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _story.dispose();
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _toggleAgreed() => setState(() {
    _agreed = !_agreed;
    if (_agreed) _consentNudge = false;
  });

  /// A tap on a waiting button: say why it waits.
  void _nudgeConsent() {
    if (!_agreed && !_consentNudge) setState(() => _consentNudge = true);
  }

  void _clearPhoneError() {
    if (_phoneError != null || _restrictedNumber != null) {
      setState(() {
        _phoneError = null;
        _restrictedNumber = null;
        _waitlistSaved = false;
      });
    }
  }

  Future<void> _continue() async {
    if (_busy != null) return;
    final number = phoneNumberFromField(_phone.text, _country);
    if (number == null) {
      setState(() => _phoneError = context.l10n.invalidMobileNumber);
      return;
    }
    setState(() {
      _busy = _Busy.phone;
      _providerError = null;
      _restrictedNumber = null;
      _waitlistSaved = false;
    });
    try {
      final challenge = await _auth.requestOtp(phone: number);
      if (!mounted) return;
      _phoneFocus.unfocus();
      await Navigator.push(
        context,
        RightToLeftTransition(
          PhoneVerification(challenge: challenge, controller: _auth),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phoneError = authErrorMessage(error, AuthAction.sendCode);
        if (isSignInRestricted(error)) _restrictedNumber = number;
      });
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _provider(String provider) async {
    if (_busy != null) return;
    final label = provider == 'apple' ? 'Apple' : 'Google';
    setState(() {
      _busy = provider == 'apple' ? _Busy.apple : _Busy.google;
      _providerError = null;
      _phoneError = null;
    });
    try {
      final result = await _auth.signIn(provider: provider);
      if (!mounted) return;
      switch (result) {
        case ProviderSignedIn():
          enterMoveraApp(context);
        case ProviderPhoneRequired(:final link):
          await Navigator.push(
            context,
            RightToLeftTransition(
              AddPhoneNumber(link: link, controller: _auth),
            ),
          );
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _providerError = authErrorMessage(
          error,
          AuthAction.providerSignIn,
          provider: label,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idle = _busy == null && _agreed;
    return AuthScaffold(
      step: 1,
      headline: '',
      headlineAccent: '',
      hero: BalloonBrandIntro(progress: _story, wordmarkKey: _wordmarkKey),
      sceneProgress: _story,
      sceneKey: _sceneKey,
      overlay: BalloonFlight(
        progress: _story,
        sceneKey: _sceneKey,
        wordmarkKey: _wordmarkKey,
      ),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.enterPhone, style: AuthText.cardTitle()),
          const SizedBox(height: 2),
          Text(context.l10n.textFourDigitCode, style: AuthText.cardSub()),
          const SizedBox(height: 14),
          AuthPhoneField(
            controller: _phone,
            focusNode: _phoneFocus,
            country: _country,
            onCountryChanged: _pickCountry,
            hasError: _phoneError != null,
            onSubmitted: (_) => _continue(),
          ),
          if (_phoneError != null) AuthErrorText(_phoneError!),
          if (_restrictedNumber != null) _waitlistRow(),
          const SizedBox(height: 16),
          // Owner round 3: the rider must tick the box before Continue,
          // Apple or Google work (stores expect an explicit consent).
          Semantics(
            key: const ValueKey('auth-consent'),
            checked: _agreed,
            label: context.l10n.consentLabel,
            onTap: _toggleAgreed,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleAgreed,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _agreed ? AuthColors.ink : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _agreed
                            ? AuthColors.ink
                            : const Color(0xFFB8C4BC),
                        width: 1.5,
                      ),
                    ),
                    child: _agreed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: context.l10n.consentPrefix,
                        children: [
                          TextSpan(
                            text: context.l10n.consentTerms,
                            recognizer: _termsTap,
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w700,
                              color: AuthColors.ink,
                            ),
                          ),
                          TextSpan(text: context.l10n.and),
                          TextSpan(
                            text: context.l10n.consentPrivacy,
                            recognizer: _privacyTap,
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w700,
                              color: AuthColors.ink,
                            ),
                          ),
                        ],
                      ),
                      style: AuthText.small().copyWith(
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_consentNudge)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  context.l10n.consentTickFirst,
                  style: AuthText.small().copyWith(color: AuthColors.error),
                ),
              ),
            ),
          const SizedBox(height: 18),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _agreed ? null : _nudgeConsent,
            child: AuthPrimaryButton(
              label: context.l10n.continueLabel,
              busy: _busy == _Busy.phone,
              onPressed: idle ? _continue : null,
            ),
          ),
          SlowServerNote(busy: _busy != null || _waitlistBusy),
          const SizedBox(height: 14),
          const AuthOrDivider(),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _agreed ? null : _nudgeConsent,
            child: Row(
              children: [
                Expanded(
                  child: AuthProviderButton(
                    label: 'Apple',
                    leading: const Icon(
                      Icons.apple,
                      color: AuthColors.ink,
                      size: 20,
                    ),
                    busy: _busy == _Busy.apple,
                    onPressed: idle ? () => _provider('apple') : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AuthProviderButton(
                    label: 'Google',
                    leading: Image.asset('assets/images/google.png'),
                    busy: _busy == _Busy.google,
                    onPressed: idle ? () => _provider('google') : null,
                  ),
                ),
              ],
            ),
          ),
          if (_providerError != null) AuthErrorText(_providerError!),
          if (_testAccounts.isNotEmpty) _testAccountList(),
        ],
      ),
    );
  }

  Widget _waitlistRow() {
    if (_waitlistSaved) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Semantics(
          liveRegion: true,
          child: Text(
            context.l10n.waitlistSaved,
            key: const ValueKey('auth-waitlist-saved'),
            style: AuthText.small().copyWith(color: AuthColors.green),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const ValueKey('auth-join-waitlist'),
          onPressed: _waitlistBusy ? null : _joinWaitlist,
          style: OutlinedButton.styleFrom(
            foregroundColor: AuthColors.ink,
            side: const BorderSide(color: AuthColors.ink),
            minimumSize: const Size(0, 40),
          ),
          child: _waitlistBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.joinWaitlist),
        ),
      ),
    );
  }

  String _statusWord(String status) => switch (status) {
    'test' => context.l10n.testStatusNew,
    'active' => context.l10n.testStatusActive,
    'suspended' => context.l10n.testStatusSuspended,
    _ => status,
  };

  Widget _testAccountList() {
    return Padding(
      key: const ValueKey('auth-test-accounts'),
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.testNumbersTitle, style: AuthText.small()),
          for (final account in _testAccounts)
            InkWell(
              key: ValueKey('auth-test-${account.phone}'),
              onTap: () => _useTestNumber(account.phone),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          displayPhoneNumber(account.phone),
                          if (account.name != null) account.name!,
                        ].join(' · '),
                        style: AuthText.small().copyWith(color: AuthColors.ink),
                      ),
                    ),
                    Text(
                      _statusWord(account.status),
                      style: AuthText.small().copyWith(
                        color: account.status == 'active'
                            ? AuthColors.green
                            : AuthColors.muted,
                      ),
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
