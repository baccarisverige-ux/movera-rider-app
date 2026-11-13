// Time limits for tool/web_lifecycle_probe.mjs (CI hang 2026-11-13).
//
// A headless Chromium can freeze (SwiftShader WebGL, a forced GC, a GPU
// stall). Playwright's page.evaluate, cdp.send and touchscreen.tap have no
// time limit of their own, so one frozen call used to run until the 30-min
// job timeout, with no log and no probe.json. Two guards:
//   - withTimeout(step, promise, ms): one call may take at most `ms`; after
//     that it throws an error that names the step.
//   - startWatchdog({ ms, out, rows }): the whole probe may take at most
//     `ms`; after that it writes the rows measured so far and the current step
//     to `out`, logs "WATCHDOG: no progress in <step>" and exits with code 3.
// No dependencies (no Playwright), so tool/tests/probe_watchdog.test.mjs can
// test it with `node --test`.
import fs from 'node:fs';

export const WATCHDOG_EXIT_CODE = 3;
export const DEFAULT_WATCHDOG_MS = 15 * 60 * 1000;
export const DEFAULT_CALL_TIMEOUT_MS = 60 * 1000;

// The current step, shared by withTimeout and the watchdog.
let currentStep = 'start';
export const setStep = (name) => {
  currentStep = name;
};
export const getStep = () => currentStep;

// A positive number from the first set value (argument, then environment),
// else the fallback.
export function pickMs(fallback, ...values) {
  for (const v of values) {
    if (v === undefined || v === null || v === '') continue;
    const n = Number(v);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return fallback;
}

export class StepTimeoutError extends Error {
  constructor(step, ms) {
    super(`PROBE TIMEOUT: "${step}" took longer than ${Math.round(ms / 1000)} s`);
    this.name = 'StepTimeoutError';
    this.step = step;
    this.ms = ms;
  }
}

// Resolves or rejects like `promise`, but rejects with StepTimeoutError when
// it has not settled after `ms`. Also marks `step` as the current step.
export function withTimeout(step, promise, ms = DEFAULT_CALL_TIMEOUT_MS) {
  setStep(step);
  let timer;
  const limit = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new StepTimeoutError(step, ms)), ms);
  });
  return Promise.race([Promise.resolve(promise), limit]).finally(() => clearTimeout(timer));
}

// Writes what was measured so far (never throws: it runs on the way out).
export function writePartial(out, rows, extra = {}) {
  try {
    fs.writeFileSync(out, JSON.stringify({ summary: null, partial: true, step: currentStep, ...extra, rows }, null, 2));
  } catch (e) {
    console.log(`  ! could not write ${out}: ${e}`);
  }
}

// Starts the whole-run watchdog. `exit` is injectable for tests.
export function startWatchdog({ ms = DEFAULT_WATCHDOG_MS, out, rows, exit = process.exit } = {}) {
  const started = Date.now();
  const timer = setTimeout(() => {
    const step = currentStep;
    writePartial(out, rows, { hung: true, watchdog: { step, afterMs: Date.now() - started, limitMs: ms } });
    console.log(`WATCHDOG: no progress in ${step} (probe ran over ${Math.round(ms / 1000)} s); ${rows.length} rows written to ${out}`);
    exit(WATCHDOG_EXIT_CODE);
  }, ms);
  return { stop: () => clearTimeout(timer) };
}
