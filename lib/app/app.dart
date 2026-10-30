import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/app/theme/app_theme.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';

/// Lets the DI container send the rider to Sign in on session expiry without
/// importing presentation (ARCH-17). Idempotent.
void registerSessionExpiredNavigation() {
  AppScope.showSignInOnSessionExpired ??= () {
    showMoveraRoot(const SignIn());
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
          builder: (context, child) => LanguageRebuild(
            code: language.code,
            child: ContentGate(
              controller: AppScope.instance.content,
              legal: AppScope.instance.legal,
              child: child!,
            ),
          ),
          home: RideRestoreGate(key: RideRestoreGate.gateKey),
        ),
      ),
    );
  }
}
