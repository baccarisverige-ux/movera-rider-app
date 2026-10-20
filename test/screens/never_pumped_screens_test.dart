import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/add_phone.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/safety/presentation/how_movera_protects_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_tips_page.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screens no test had ever built. The first one pumped — phone verification —
/// turned out to overflow by 46px with a dead control on it, so the rest are
/// worth building too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final screens = <String, Widget Function()>{
    'Sign in': () => const SignIn(),
    'Phone verification': () => const PhoneVerification(phoneNumber: '+46701234567'),
    'Add phone number (Apple/Google)': () => const AddPhoneNumber(
          link: ProviderLink(provider: 'apple', linkToken: 'link', name: 'Sara Lind'),
        ),
    'Rider name': () => const RiderNameScreen(initialName: 'Sara Lind'),
    'Add place': () => const AddPlace(),
    'How Movera protects you': () => const HowMoveraProtectsPage(),
    'Safety tips': () => const SafetyTipsPage(),
    'Help articles': () => const HelpArticles(),
    'How can we help': () => const HowCanWeHelp(),
    'Select support ride': () => const SelectSupportRide(),
  };

  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
  ]) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key} builds at ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              minTextAdapt: true,
              splitScreenMode: true,
              builder: (_, __) => MaterialApp(home: entry.value()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 80));

          expect(
            tester.takeException(),
            isNull,
            reason:
                '${entry.key} threw at '
                '${viewport.width.toInt()}x${viewport.height.toInt()}',
          );
        },
      );
    }
  }
}
