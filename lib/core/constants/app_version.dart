/// The running build's version for telemetry (CODE-20). The shipped builds
/// (android-release-signing.yml, publish-web-live.yml) pass the pubspec
/// version with `--dart-define=MOVERA_APP_VERSION=<version>`; local and CI
/// check builds report `dev`, never a version they are not.
const appVersion = String.fromEnvironment(
  'MOVERA_APP_VERSION',
  defaultValue: 'dev',
);
