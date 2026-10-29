#!/usr/bin/env node
// Owner bug 9 (2026-10-29): on the web the code field must never focus itself, and EVERY tap on it must open the
// keyboard: the first tap, a tap after the keyboard was closed, after a wrong code and after "Resend code".
// A browser opens the keyboard only for a focus() that runs inside the user's tap, so every focus() is logged with
// the DOM event it ran in; each tap must give a focus() on an INPUT during pointerup.
//
// Chromium with iPhone emulation (WebKit cannot be downloaded in the cloud sessions). Needs `playwright`, a web build
// served at URL against a staging server with test numbers, and the screen positions of the build:
//   node tool/otp_tap_browser_test.cjs URL PHONE PHONE_Y CONSENT_Y CONTINUE_Y PIN_Y RESEND_Y PIN_Y_AFTER_RESEND
// Exit code 1 when any tap did not focus.
const pw = require('playwright');
const [url, phone, phoneY, consentY, continueY, pinY, resendY, pinY2] = process.argv.slice(2);
(async () => {
  const browser = await pw.chromium.launch();
  const context = await browser.newContext({ ...pw.devices['iPhone 13'], ignoreHTTPSErrors: true, locale: 'sv-SE' });
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'vendor', { get: () => 'Apple Computer, Inc.' });
    Object.defineProperty(navigator, 'platform', { get: () => 'iPhone' });
    window.__log = [];
    const focus = HTMLElement.prototype.focus;
    HTMLElement.prototype.focus = function (options) {
      window.__log.push(`focus ${this.tagName} during=${window.event ? window.event.type : 'NONE'}`);
      return focus.call(this, options);
    };
  });
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForTimeout(14000);
  const take = () => page.evaluate(() => window.__log.splice(0));
  const tap = async (y, x = 195) => { await page.touchscreen.tap(x, +y); await page.waitForTimeout(800); return take(); };
  const focusedInTap = (log) => log.includes('focus INPUT during=pointerup');
  await tap(phoneY, 260);
  await page.keyboard.type(phone);
  await tap(consentY, 32);
  await tap(continueY);
  await page.waitForTimeout(3000);
  const result = {};
  result.noFocusOnOpen = !(await take()).some((line) => line.startsWith('focus INPUT'));
  result.firstTap = focusedInTap(await tap(pinY));
  await page.keyboard.type('99');
  await page.evaluate(() => document.activeElement && document.activeElement.blur()); // keyboard closed
  await page.waitForTimeout(500);
  await take();
  result.afterKeyboardClosed = focusedInTap(await tap(pinY));
  await page.keyboard.type('99');
  await page.waitForTimeout(1500);
  await take();
  result.afterWrongCode = focusedInTap(await tap(pinY));
  await page.waitForTimeout(31000);
  await tap(resendY);
  await page.waitForTimeout(2000);
  await take();
  result.afterResend = focusedInTap(await tap(pinY2 || pinY));
  console.log(JSON.stringify(result));
  await browser.close();
  process.exit(Object.values(result).every(Boolean) ? 0 : 1);
})();
