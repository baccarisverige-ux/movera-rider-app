import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/add_phone.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/balloon_brand_intro.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

String? _frenchNumberFromField(String typed) {
  final digits = typed.replaceAll(RegExp(r'\\s+'), '');
  final national = digits.length == 10 && digits.startsWith('0')
      ? digits.substring(1)
      : digits;

  if (!RegExp(r'^[67][0-9]{8}$').hasMatch(national)) {
    return null;
  }
  return '+33$national';
}

/// Step 1 for everyone: one phone field for new and returning riders, with
/// Apple and Google underneath.
class SignIn extends StatefulWidget {
  const SignIn({super.key, this.controller});

  final AuthController? controller;

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
  String _countryCode = 'SE';
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();

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
  String? _providerError;

  @override
  void initState() {
    super.initState();
    _auth = widget.controller ?? AppScope.instance.auth;
    _phone.addListener(_clearPhoneError);
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

  void _clearPhoneError() {
    if (_phoneError != null) setState(() => _phoneError = null);
  }

  Future<void> _continue() async {
    if (_busy != null) return;
    final number = _countryCode == 'FR'
        ? _frenchNumberFromField(_phone.text)
        : swedishNumberFromField(_phone.text);
    if (number == null) {
      setState(
        () => _phoneError = _countryCode == 'FR'
            ? 'Enter a valid French mobile number.'
            : context.l10n.invalidSwedishMobile,
      );
      return;
    }
    setState(() {
      _busy = _Busy.phone;
      _providerError = null;
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
      setState(
        () => _phoneError = authErrorMessage(error, AuthAction.sendCode),
      );
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
    final idle = _busy == null;
    return AuthScaffold(
      step: 1,
      headline: '',
      headlineAccent: '',
      hero: BalloonBrandIntro(progress: _story),
      sceneProgress: _story,
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.enterPhone, style: AuthText.cardTitle()),
          const SizedBox(height: 2),
          Text(context.l10n.textFourDigitCode, style: AuthText.cardSub()),
          const SizedBox(height: 14),
          AuthPhoneField(
            countryCode: _countryCode,
            onCountryChanged: (country) {
              setState(() {
                _countryCode = country;
                _phone.clear();
                _phoneError = null;
              });
            },
            controller: _phone,
            focusNode: _phoneFocus,
            hasError: _phoneError != null,
            onSubmitted: (_) => _continue(),
          ),
          if (_phoneError != null) AuthErrorText(_phoneError!),
          const SizedBox(height: 12),
          AuthPrimaryButton(
            label: context.l10n.continueLabel,
            busy: _busy == _Busy.phone,
            onPressed: idle ? _continue : null,
          ),
          const SizedBox(height: 14),
          const AuthOrDivider(),
          const SizedBox(height: 10),
          Row(
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
          if (_providerError != null) AuthErrorText(_providerError!),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              text: context.l10n.byContinuing,
              children: [
                TextSpan(
                  text: context.l10n.termsLink,
                  recognizer: _termsTap,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AuthColors.ink,
                  ),
                ),
                TextSpan(text: context.l10n.and),
                TextSpan(
                  text: context.l10n.privacyPolicy,
                  recognizer: _privacyTap,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AuthColors.ink,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: AuthText.small(),
          ),
        ],
      ),
    );
  }
}
