// Runs a Flutter web bootstrap template (web/flutter_bootstrap.js) under
// node with a stub loader and prints the config it loads the app with.
// Without the file, `flutter build web` uses Flutter's own template; its
// offline-first form (the default PWA strategy) is used instead.
const fs = require('fs');
const vm = require('vm');

const path = process.argv[2];
const flutterDefault = [
  '{{flutter_js}}',
  '{{flutter_build_config}}',
  '_flutter.loader.load({',
  '  serviceWorkerSettings: {',
  '    serviceWorkerVersion: {{flutter_service_worker_version}}',
  '  }',
  '});',
].join('\n');
const template = fs.existsSync(path)
  ? fs.readFileSync(path, 'utf8')
  : flutterDefault;
const calls = [];
const source = template
  .replace('{{flutter_js}}',
    'var _flutter = {loader: {load: (c) => calls.push(c === undefined ? null : c)}};')
  .replace('{{flutter_build_config}}', '_flutter.buildConfig = {builds: []};')
  .replace('{{flutter_service_worker_version}}', '"1"');
vm.runInNewContext(source, {calls});
process.stdout.write(JSON.stringify({calls}));
