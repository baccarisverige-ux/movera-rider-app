import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// web/index.html holds Google's sign-in script back until the first
/// Google tap (it costs about 100 kB at every start); this lets it load.
void releaseGoogleSignInScript() {
  final release = globalContext['moveraLoadGoogleSignIn'];
  if (release != null && release.isA<JSFunction>()) {
    (release as JSFunction).callAsFunction();
  }
}
