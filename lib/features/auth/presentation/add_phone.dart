import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/application/phone_country_default.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// First Apple or Google sign-in: a phone number is required once, so the
/// driver and Safety features can always reach the rider. There is no skip.
class AddPhoneNumber extends StatefulWidget {
  const AddPhoneNumber({super.key, required this.link, this.controller});

  final ProviderLink link;
  final AuthController? controller;

  @override
  State<AddPhoneNumber> createState() => _AddPhoneNumberState();
}

class _AddPhoneNumberState extends State<AddPhoneNumber> {
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
      _error = null;
    });
  }
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaultCountry());
    _auth = widget.controller ?? AppScope.instance.auth;
    _phone.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final number = phoneNumberFromField(_phone.text, _country);
    if (number == null) {
      setState(() => _error = context.l10n.invalidMobileNumber);
      return;
    }
    setState(() => _busy = true);
    try {
      final challenge = await _auth.requestOtp(phone: number, link: widget.link);
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
      setState(() => _error = authErrorMessage(error, AuthAction.sendCode));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final who = link.name == null
        ? context.l10n.signedInWith(link.providerLabel)
        : context.l10n.signedInAs(link.name!);
    return AuthScaffold(
      step: 1,
      onBack: () => Navigator.of(context).maybePop(),
      headline: context.l10n.oneNumberHead,
      headlineAccent: context.l10n.oneNumberAccent,
      lede: Text(context.l10n.driverUsesPhone),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF6F0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AuthColors.ink,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      link.provider == 'apple' ? Icons.apple : Icons.g_mobiledata_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      who,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F6B40),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded, size: 15, color: Color(0xFF0F6B40)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(context.l10n.addYourPhone, style: AuthText.cardTitle()),
          const SizedBox(height: 2),
          Text(context.l10n.onlyOnceCode, style: AuthText.cardSub()),
          const SizedBox(height: 14),
          AuthPhoneField(
            controller: _phone,
            focusNode: _phoneFocus,
            country: _country,
            onCountryChanged: _pickCountry,
            hasError: _error != null,
            onSubmitted: (_) => _sendCode(),
          ),
          if (_error != null) AuthErrorText(_error!),
          const SizedBox(height: 12),
          AuthPrimaryButton(
            label: context.l10n.sendCode,
            busy: _busy,
            onPressed: _sendCode,
          ),
        ],
      ),
    );
  }
}
