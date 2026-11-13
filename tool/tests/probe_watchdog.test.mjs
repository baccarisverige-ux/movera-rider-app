// Tests for tool/probe_watchdog.mjs (the web memory probe's time limits).
// Run: node --test tool/tests/probe_watchdog.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  DEFAULT_CALL_TIMEOUT_MS,
  DEFAULT_WATCHDOG_MS,
  StepTimeoutError,
  WATCHDOG_EXIT_CODE,
  getStep,
  pickMs,
  setStep,
  startWatchdog,
  withTimeout,
} from '../probe_watchdog.mjs';

const moduleUrl = pathToFileURL(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'probe_watchdog.mjs')).href;
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'probe-watchdog-'));

test('defaults: 15 min run, 60 s a call, exit code 3', () => {
  assert.equal(DEFAULT_WATCHDOG_MS, 15 * 60 * 1000);
  assert.equal(DEFAULT_CALL_TIMEOUT_MS, 60 * 1000);
  assert.equal(WATCHDOG_EXIT_CODE, 3);
});

test('pickMs: first positive value wins, else the fallback', () => {
  assert.equal(pickMs(5, undefined, '', '7'), 7);
  assert.equal(pickMs(5, '9', '7'), 9);
  assert.equal(pickMs(5, 'abc', '0', '-1'), 5);
  assert.equal(pickMs(5), 5);
});

test('withTimeout: passes a value through and marks the step', async () => {
  assert.equal(await withTimeout('quick step', Promise.resolve(42), 1000), 42);
  assert.equal(getStep(), 'quick step');
});

test('withTimeout: passes the call\'s own error through', async () => {
  await assert.rejects(withTimeout('failing step', Promise.reject(new Error('own')), 1000), /own/);
});

test('withTimeout: a call that never settles throws an error naming the step', async () => {
  const never = new Promise(() => {});
  const t0 = Date.now();
  await assert.rejects(withTimeout('c3 finding / cdp HeapProfiler.collectGarbage', never, 50), (e) => {
    assert.ok(e instanceof StepTimeoutError);
    assert.equal(e.step, 'c3 finding / cdp HeapProfiler.collectGarbage');
    assert.match(e.message, /PROBE TIMEOUT: "c3 finding \/ cdp HeapProfiler\.collectGarbage"/);
    return true;
  });
  assert.ok(Date.now() - t0 < 1000);
});

test('watchdog: stop() keeps it from firing', async () => {
  let code;
  const dog = startWatchdog({ ms: 30, out: path.join(tmp(), 'p.json'), rows: [], exit: (c) => { code = c; } });
  dog.stop();
  await new Promise((r) => setTimeout(r, 80));
  assert.equal(code, undefined);
});

test('watchdog: writes rows + step and exits 3 (injected exit)', async () => {
  const out = path.join(tmp(), 'p.json');
  const rows = [{ step: 0, label: 'boot' }];
  let code;
  startWatchdog({ ms: 30, out, rows, exit: (c) => { code = c; } });
  setStep('c2 cancel / press "Skip"');
  rows.push({ step: 1, label: 'home' });
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(code, 3);
  const data = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(data.hung, true);
  assert.equal(data.summary, null);
  assert.equal(data.step, 'c2 cancel / press "Skip"');
  assert.equal(data.watchdog.step, 'c2 cancel / press "Skip"');
  assert.equal(data.rows.length, 2);
});

test('watchdog: a real hung process exits with code 3 and logs the step', () => {
  const dir = tmp();
  const out = path.join(dir, 'probe.json');
  const script = [
    `import { startWatchdog, withTimeout } from ${JSON.stringify(moduleUrl)};`,
    'const rows = [{ step: 0, label: "boot" }];',
    `startWatchdog({ ms: 200, out: ${JSON.stringify(out)}, rows });`,
    // A frozen browser call: never settles; the per-call limit is longer.
    'await withTimeout("c1 home / read state", new Promise(() => setInterval(() => {}, 1000)), 60000);',
  ].join('\n');
  const file = path.join(dir, 'hang.mjs');
  fs.writeFileSync(file, script);
  const r = spawnSync(process.execPath, [file], { encoding: 'utf8', timeout: 20000 });
  assert.equal(r.status, 3, r.stderr);
  assert.match(r.stdout, /WATCHDOG: no progress in c1 home \/ read state/);
  const data = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(data.hung, true);
  assert.equal(data.rows.length, 1);
});
