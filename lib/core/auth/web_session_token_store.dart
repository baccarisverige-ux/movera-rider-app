import 'package:movera_rider/core/auth/token_store.dart';

import 'package:movera_rider/core/auth/web_session_token_store_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/auth/web_session_token_store_web.dart';

/// The browser token store, or null where there is no browser.
///
/// Contract v0.18.5, owner G1-D1 "Stay signed in (Recommended)": web keeps
/// the tokens in localStorage (`BrowserTokenStore`), so the rider stays
/// signed in after a reload and after the tab, the browser or the
/// Home-screen app is fully closed, like the driver app. Sign-out or 30
/// days unused end it.
///
/// The trade-off, accepted with that decision: anyone who later opens the
/// app in the same browser profile (a shared or borrowed computer) is
/// signed in as this rider until someone signs out. Earlier builds used
/// sessionStorage, which ends with the tab, to avoid exactly that.
/// - Sign-out and session expiry call [TokenStore.clear], which removes
///   both keys from localStorage and from sessionStorage.
/// - Every tab of the app shares the one session.
/// - Unlike a cookie it is never sent with requests, so it adds no CSRF
///   surface.
/// - Script injected into the page could read it, as before; the tokens
///   now outlive the page until sign-out or the session's own expiry.
/// - In a Safari tab (not the Home-screen app) Safari may delete a site's
///   localStorage after about a week without a visit; the rider then signs
///   in again.
/// A session saved in sessionStorage by an earlier build is moved over on
/// the first read, so the update signs nobody out.
TokenStore? webSessionTokenStore() => createWebSessionTokenStore();
