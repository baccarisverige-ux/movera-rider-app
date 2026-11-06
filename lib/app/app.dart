import 'package:flutter/material.dart';
import 'package:movera_rider/core/preview/preview_mode.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/app/theme/app_theme.dart';
import 'package:movera_rider/core/platform/safe_area_insets.dart';
import 'package:movera_rider/features/calls/application/rider_trip_calls.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/features/account_status/presentation/account_status_screens.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';

/// Lets the DI container send the rider to Sign in on session expiry without
/// importing presentation (ARCH-17). Idempotent.
void registerSessionExpiredNavigation() {
  AppScope.showSignInOnSessionExpired ??= () {
    showMoveraRoot(const SignIn());
  };
  // v0.18.38 §62 (fix job 8, owner G15 "Both rider and driver"): the
  // driver's in-app call opens the call screen with Answer / Decline over
  // whatever screen is up.
  // Reading tripCall creates the calls hub on the live wire.
  if (AppScope.instance.tripCall == null) return;
  RiderTripCalls.instance?.onIncoming ??= (session) {
    final context = moveraNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      TripCallScreen.open(context, session);
    }
  };
}

class MoveraApp extends StatelessWidget {
  const MoveraApp({super.key});

  static final _homeHistoryObserver = HomeHistoryObserver();

  @override
  Widget build(BuildContext context) {
    registerSessionExpiredNavigation();
    final language = AppScope.instance.language;
    return MoveraScreenUtilInit(
      builder: (_, child) => ListenableBuilder(
        listenable: language,
        builder: (context, _) => MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          navigatorKey: moveraNavigatorKey,
          navigatorObservers: [_homeHistoryObserver],
          // Q48: the rider's choice, else the pickup zone's default.
          locale: language.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          theme: moveraTheme(),
          // v0.10.0 Content: update block, terms and update messages.
          // Owner 2026-10-30 "Map under the strip": on the web the page's
          // safe-area insets reach MediaQuery (the engine reports none).
          builder: (context, child) => SafeAreaFromPage(
            child: LanguageRebuild(
              code: language.code,
              child: ModerationGate(
                child: ContentGate(
                  controller: AppScope.instance.content,
                  legal: AppScope.instance.legal,
                  // v0.18.40 §64 (fix job 10): the rider's level (warning
                  // banner, paused / blocked screen) over every screen.
                  // Contract v0.18.25: an admin preview shows a "Preview" strip.
                  child: PreviewMode.current.active
                      ? Column(
                          children: [
                            const PreviewBanner(),
                            Expanded(
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                child: child!,
                              ),
                            ),
                          ],
                        )
                      : child!,
                ),
              ),
            ),
          ),
          home: RideRestoreGate(key: RideRestoreGate.gateKey),
        ),
      ),
    );
  }
}
