import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:pinput/pinput.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Step 2: enter the 4-digit code. Verify unlocks at four digits; resend
/// unlocks when the server's retry window has passed.
class PhoneVerification extends StatefulWidget {
  const PhoneVerification({
    super.key,
    this.challenge,
    this.phoneNumber,
    this.controller,
    this.clock,
  });

  final OtpChallenge? challenge;
  final String? phoneNumber;
  final AuthController? controller;

  /// The wall clock the resend window is measured on (tests).
  final DateTime Function()? clock;

  @override
  State<PhoneVerification> createState() => _PhoneVerificationState();
}

class _PhoneVerificationState extends State<PhoneVerification> {
  late final AuthController _auth;
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  OtpChallenge? _challenge;
  int _secondsUntilResend = 0;
  Timer? _ticker;
  bool _submitting = false;
  bool _resending = false;
  String? _error;
  String? _info;

  String? get _phone => _challenge?.phone ?? widget.phoneNumber;

  @override
  void initState() {
    super.initState();
    _auth = widget.controller ?? AppScope.instance.auth;
    _challenge = widget.challenge;
    final challenge = _challenge;
    if (challenge != null) _startResendWindow(challenge.retryAfter);
    _pin.addListener(_pinChanged);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _pinChanged() {
    setState(() {
      if (_error != null) _error = null;
    });
  }

  /// Counts the server's retry window down once a second.
  ///
  /// rider-r4-11: a suspended app or a throttled web tab fires the timer
  /// once after a long gap, so the wait left is measured, not counted per
  /// callback: whichever of the wall clock and the timer's own tick count
  /// has seen more time pass.
  void _startResendWindow(Duration wait) {
    _ticker?.cancel();
    final seconds =
        wait.inSeconds + (wait.inMilliseconds % 1000 == 0 ? 0 : 1);
    _secondsUntilResend = seconds;
    if (seconds <= 0) return;
    final now = widget.clock ?? DateTime.now;
    final allowedAt = now().add(Duration(seconds: seconds));
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final byClock = allowedAt.difference(now()).inMilliseconds;
      final left = min(seconds - timer.tick, (byClock / 1000).ceil());
      setState(() => _secondsUntilResend = max(0, left));
      if (_secondsUntilResend <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    if (_resending) return;
    final phone = _phone?.trim();
    if (phone == null || phone.isEmpty) {
      setState(() => _error = context.l10n.reenterPhone);
      return;
    }
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      final next = await _auth.requestOtp(phone: phone, link: _challenge?.link);
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _challenge = next;
        _info = context.l10n.newCodeSent;
      });
      _startResendWindow(next.retryAfter);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(error, AuthAction.sendCode));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    if (_submitting) return;
    final challenge = _challenge;
    final code = _pin.text.trim();
    if (challenge == null) {
      setState(() => _error = context.l10n.requestNewCode);
      return;
    }
    // rider-u73: no device-clock expiry check; the server answers 410 for
    // an expired code and authErrorMessage says so.
    if (!RidePin.isValidFormat(code)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await _auth.verifyOtp(challenge: challenge, code: code);
      if (!mounted) return;
      _ticker?.cancel();
      if (result.isNewRider) {
        // Keeps the root gate mounted (see enterMoveraApp).
        showMoveraRoot(
          RiderNameScreen(initialName: challenge.link?.name),
          navigator: Navigator.of(context),
        );
      } else {
        enterMoveraApp(context);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(error, AuthAction.verifyCode));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    final complete = RidePin.isValidFormat(_pin.text.trim());
    // rider-r3-10: no way back while the code is being checked. Leaving
    // here unmounted the screen that opens the app (or the new-rider name
    // step) once the verify signs the rider in, so a signed-in rider was
    // left on the Sign in form.
    return PopScope(
      canPop: !_submitting,
      child: _content(context, phone, complete),
    );
  }

  Widget _content(BuildContext context, String? phone, bool complete) {
    return AuthScaffold(
      step: 2,
      onBack: () => Navigator.of(context).maybePop(),
      headline: context.l10n.enterYourCodeHead,
      headlineAccent: context.l10n.enterYourCodeAccent,
      lede: phone == null || phone.trim().isEmpty
          ? Text(context.l10n.codeSentToPhone)
          : Text.rich(
              TextSpan(
                text: context.l10n.sentTo,
                children: [
                  TextSpan(
                    text: displayPhoneNumber(phone.trim()),
                    style: const TextStyle(
                      color: AuthColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pinput(
            length: 4,
            controller: _pin,
            focusNode: _pinFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            forceErrorState: _error != null,
            onCompleted: (_) => setState(() {}),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            defaultPinTheme: _box(AuthColors.field, Colors.transparent),
            focusedPinTheme: _box(Colors.white, AuthColors.deepGreen, ring: true),
            submittedPinTheme: _box(AuthColors.field, Colors.transparent),
            errorPinTheme: _box(Colors.white, AuthColors.error),
          ),
          if (_error != null) AuthErrorText(_error!),
          if (_info != null && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _info!,
                  textAlign: TextAlign.center,
                  style: AuthText.cardSub().copyWith(color: AuthColors.green),
                ),
              ),
            ),
          if (AppEnv.current.authPreview) ...[
            const SizedBox(height: 12),
            AuthNote(
              icon: Icons.info_outline_rounded,
              text: context.l10n.demoCode,
            ),
          ],
          const SizedBox(height: 16),
          Center(child: _resendRow()),
          const SizedBox(height: 16),
          AuthNote(
            icon: Icons.verified_user_outlined,
            text: context.l10n.neverAskCode,
          ),
          const SizedBox(height: 14),
          AuthPrimaryButton(
            label: context.l10n.verify,
            showArrow: false,
            busy: _submitting,
            onPressed: complete ? _verify : null,
          ),
        ],
      ),
    );
  }

  PinTheme _box(Color fill, Color border, {bool ring = false}) {
    return PinTheme(
      width: 68,
      height: 66,
      textStyle: GoogleFonts.poppins(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AuthColors.ink,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
        boxShadow: ring
            ? const [BoxShadow(color: Color(0x1A12804F), spreadRadius: 4)]
            : null,
      ),
    );
  }

  Widget _resendRow() {
    final wait = _secondsUntilResend;
    final style = AuthText.cardSub();
    if (_resending) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: AuthColors.deepGreen),
      );
    }
    if (wait > 0) {
      final mm = wait ~/ 60;
      final ss = (wait % 60).toString().padLeft(2, '0');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 16, color: AuthColors.muted),
          const SizedBox(width: 7),
          Text.rich(
            TextSpan(
              text: context.l10n.resendCodeIn,
              children: [
                TextSpan(
                  text: '$mm:$ss',
                  style: const TextStyle(
                    color: AuthColors.green,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            style: style,
          ),
        ],
      );
    }
    return TextButton(
      onPressed: _resend,
      style: TextButton.styleFrom(
        foregroundColor: AuthColors.green,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      child: Text(
        context.l10n.resendCode,
        style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
