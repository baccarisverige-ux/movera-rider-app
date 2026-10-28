import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/content/rider_content.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

const _ink = Color(0xFF1D252C);
const _muted = Color(0xFF5C656C);
const _cta = Color(0xFF11181D);
const _soft = Color(0xFFF4F6F8);
const _sos = Color(0xFFC62828);

TextStyle _text(double size, {FontWeight weight = FontWeight.w400, Color? c}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: c ?? _ink,
      height: 1.35,
    );

/// The store page of this app. The shipped builds may pass their own with
/// `--dart-define=MOVERA_STORE_URL=<url>`.
String storeUrl([TargetPlatform? platform]) {
  const own = String.fromEnvironment('MOVERA_STORE_URL');
  if (own.isNotEmpty) return own;
  final p = platform ?? defaultTargetPlatform;
  if (!kIsWeb && (p == TargetPlatform.iOS || p == TargetPlatform.macOS)) {
    return 'https://apps.apple.com/app/movera-rider';
  }
  return 'https://play.google.com/store/apps/details?id=com.movera.rider';
}

Future<void> openStore() async {
  try {
    await launchUrl(
      Uri.parse(storeUrl()),
      mode: LaunchMode.externalApplication,
    );
  } catch (error) {
    AppLog.warning('rider_content.ignored', extra: {'error': error.toString()});
  }
}

/// Puts the content rules (contract v0.10.0 §19) over the whole app: the
/// "Update the app" block, the terms to accept, and the small update
/// messages. Neither full screen shows during a trip, and both keep the
/// 112 button, so SOS is always reachable.
class ContentGate extends StatelessWidget {
  const ContentGate({
    super.key,
    required this.controller,
    required this.child,
    this.onCallEmergency,
    this.onOpenStore,
  });

  final RiderContentController controller;
  final Widget child;
  final VoidCallback? onCallEmergency;
  final VoidCallback? onOpenStore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final decision = controller.decision;
        final sos =
            onCallEmergency ??
            () => EmergencyCallService.shared.callEmergencyNumber();
        final store = onOpenStore ?? openStore;
        Widget? cover;
        if (decision.blockForUpdate) {
          cover = UpdateRequiredScreen(onOpenStore: store, onCallSos: sos);
        } else if (decision.acceptTerms case final legal?) {
          cover = TermsAcceptScreen(
            item: legal,
            onAccept: controller.acceptTerms,
            onCallSos: sos,
          );
        }
        final notice = decision.tripUpdateNotice
            ? UpdateNotice(text: context.l10n.contentUpdateAfterTrip)
            : decision.recommendUpdate
            ? UpdateNotice(
                text: context.l10n.contentUpdateRecommended,
                onUpdate: store,
                onClose: controller.closeRecommendedUpdate,
              )
            : null;
        return Stack(
          children: [
            // The app below stays mounted but cannot be reached.
            ExcludeSemantics(
              excluding: cover != null,
              child: AbsorbPointer(absorbing: cover != null, child: child),
            ),
            if (cover == null && notice != null)
              Positioned(
                left: 12,
                right: 12,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: notice,
                  ),
                ),
              ),
            if (cover != null) Positioned.fill(child: cover),
          ],
        );
      },
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('content-sos'),
      onPressed: onTap,
      icon: const Icon(Icons.sos_rounded, color: _sos),
      label: Text(
        context.l10n.rcCall112,
        style: _text(14, weight: FontWeight.w600, c: _sos),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _cta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: _text(16, weight: FontWeight.w600, c: Colors.white),
              ),
      ),
    );
  }
}

/// Below the minimum version: the app is blocked; only the store and 112.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.onOpenStore,
    required this.onCallSos,
  });

  final VoidCallback onOpenStore;
  final VoidCallback onCallSos;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('content-update-required'),
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _SosButton(onTap: onCallSos),
              ),
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: _soft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  size: 44,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.contentUpdateTitle,
                textAlign: TextAlign.center,
                style: _text(26, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.contentUpdateBody,
                textAlign: TextAlign.center,
                style: _text(15, c: _muted),
              ),
              const Spacer(),
              _PrimaryButton(
                key: const Key('content-open-store'),
                label: context.l10n.contentUpdateStore,
                onTap: onOpenStore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New terms published with reaccept: shown at app start, until accepted.
class TermsAcceptScreen extends StatefulWidget {
  const TermsAcceptScreen({
    super.key,
    required this.item,
    required this.onAccept,
    required this.onCallSos,
  });

  final ContentItem item;
  final Future<bool> Function() onAccept;
  final VoidCallback onCallSos;

  @override
  State<TermsAcceptScreen> createState() => _TermsAcceptScreenState();
}

class _TermsAcceptScreenState extends State<TermsAcceptScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await widget.onAccept();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Material(
      key: const Key('content-terms'),
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.contentTermsTitle,
                      style: _text(13, weight: FontWeight.w600, c: _muted),
                    ),
                  ),
                  _SosButton(onTap: widget.onCallSos),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.title, style: _text(24, weight: FontWeight.w700)),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _soft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: Text(item.textIn(L10n.code), style: _text(14.5)),
                  ),
                ),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    context.l10n.contentTermsFailed,
                    style: _text(13, c: _sos),
                  ),
                ),
              const SizedBox(height: 16),
              _PrimaryButton(
                key: const Key('content-terms-accept'),
                label: context.l10n.contentTermsAccept,
                onTap: _accept,
                busy: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small message: below the recommended version (closable), or below
/// the minimum during a trip (the block follows the trip).
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({
    super.key,
    required this.text,
    this.onUpdate,
    this.onClose,
  });

  final String text;
  final VoidCallback? onUpdate;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('content-update-notice'),
      color: _cta,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: _text(13.5, c: Colors.white)),
            ),
            if (onUpdate != null)
              TextButton(
                onPressed: onUpdate,
                child: Text(
                  context.l10n.contentUpdateNow,
                  style: _text(13.5, weight: FontWeight.w700, c: Colors.white),
                ),
              ),
            if (onClose != null)
              // No tooltip: the gate sits above the navigator's overlay.
              IconButton(
                key: const Key('content-update-close'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
