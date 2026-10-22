{{flutter_js}}
{{flutter_build_config}}
// rider-21: load the app without serviceWorkerSettings. With them (the
// default `flutter build web` template), Flutter's loader registers its
// flutter_service_worker.js at the app root whenever any worker covers the
// page. That replaced firebase-messaging-sw.js, which Firebase web push
// registers at the same root scope; Flutter's worker then unregisters itself
// and reloads every tab, so each cold start reloaded once and lost the push
// subscription. The app is not an offline PWA (index.html removes old
// Flutter workers), so nothing else needs the loader's worker.
_flutter.loader.load();
