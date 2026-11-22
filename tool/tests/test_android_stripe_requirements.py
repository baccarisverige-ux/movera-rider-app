"""The Android build meets the flutter_stripe 11.5.0 requirements.

README "Requirements > Android" (same check as the Driver,
Movera-driver-app#666). Without step 7, `flutter build apk --release` stops
at :app:minifyReleaseWithR8 with "Missing class
com.stripe.android.pushProvisioning.PushProvisioningActivity$g ...".
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ANDROID = ROOT / 'android'
APP = ANDROID / 'app'


def read(path):
    return path.read_text(encoding='utf-8')


class StripeAndroidRequirements(unittest.TestCase):
    def test_step7_r8_rules_for_push_provisioning(self):
        lines = read(APP / 'proguard-rules.pro').splitlines()
        for name in (
            'PushProvisioningActivity$g',
            'PushProvisioningActivityStarter$Args',
            'PushProvisioningActivityStarter$Error',
            'PushProvisioningActivityStarter',
            'PushProvisioningEphemeralKeyProvider',
        ):
            self.assertIn(
                '-dontwarn com.stripe.android.pushProvisioning.' + name,
                lines, name)

    def test_step7_release_build_uses_the_rules_with_r8_on(self):
        gradle = read(APP / 'build.gradle.kts')
        build_types = gradle[gradle.index('buildTypes {'):
                             gradle.index('\nflutter {')]
        release = build_types[build_types.index('release {'):]
        self.assertIn('proguardFiles("proguard-rules.pro")', release)
        # Minify / R8 is never switched off to get around a missing rule.
        self.assertNotIn('isMinifyEnabled = false', gradle)
        self.assertNotIn('isShrinkResources = false', gradle)

    def test_step8_no_r8_full_mode(self):
        lines = read(ANDROID / 'gradle.properties').splitlines()
        self.assertIn('android.enableR8.fullMode=false', lines)

    def test_step6_fragment_activity(self):
        activity = read(APP / 'src/main/kotlin/com/movera/rider/MainActivity.kt')
        self.assertIn('class MainActivity : FlutterFragmentActivity()',
                      activity)

    def test_step4_appcompat_theme_light_and_night(self):
        manifest = read(APP / 'src/main/AndroidManifest.xml')
        self.assertIn('android:resource="@style/NormalTheme"', manifest)
        pattern = re.compile(
            r'<style name="NormalTheme" '
            r'parent="Theme\.(AppCompat|MaterialComponents)[.\w]*">')
        for folder in ('values', 'values-night'):
            styles = read(APP / 'src/main/res' / folder / 'styles.xml')
            self.assertRegex(styles, pattern, folder)


if __name__ == '__main__':
    unittest.main()
