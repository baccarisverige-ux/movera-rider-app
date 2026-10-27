// The back2 sequence that ended on a cancelled Waiting screen: admin cancel, then goto (hash dropped), tap "Back to home".
import { open, signIn, labels, tap, has, save, driver, adminCancelActive } from "./lib.mjs";
const S = process.env.P5_DIR || "p5-out";
const OUT = process.env.OUT || S + "/restore2"; const site = process.env.SITE || "http://localhost:7101/";
const { browser, page, net, errors, logs } = await open({ site, out: OUT, canvaskit: process.env.CK || S + "/web-base/canvaskit" });
const d = await driver(); const out = [];
async function toWaiting() {
  await tap(page, /^Where to\?/); await page.waitForTimeout(1200);
  await page.mouse.click(160, 146); await page.keyboard.type("Odenplan", { delay: 50 }); await page.waitForTimeout(1200);
  await tap(page, /^Odenplan/); await has(page, /^Select /); await tap(page, /^Select Movera/); await has(page, /^Confirm and search$/);
  await d.online(); await tap(page, /^Confirm and search$/); await has(page, /^Cancel request$/, 20000);
  let a = null; for (let i = 0; i < 20 && !a; i++) { a = await d.acceptAny(); if (!a) await page.waitForTimeout(1000); }
  await has(page, /^Cancel ride$/, 20000);
}
try {
  await signIn(page, net, site, process.env.PHONE || "701740610");
  await tap(page, /^Not now$/, 3000).catch(() => {}); await tap(page, /^Back to home$/, 3000).catch(() => {});
  for (let i = 0; i < Number(process.env.N || 4); i++) {
    await has(page, /^Where to\?/, 20000);
    await toWaiting(); await page.waitForTimeout(1500);
    await adminCancelActive(); await d.offline().catch(() => {});
    await page.goto(site + `?p5=${Date.now()}`); await page.waitForTimeout(9000);
    await tap(page, /^Not now$/, 3000).catch(() => {}); await tap(page, /^Done$/, 2000).catch(() => {});
    logs.push(`${Date.now()} ---- BEFORE BACK TO HOME TAP`); const tapped = await tap(page, /^Back to home$/, 3000).catch(() => null); logs.push(`${Date.now()} ---- TAPPED ${tapped}`);
    const seen = [];
    for (const t of [2, 10, 25]) { await page.waitForTimeout(t === 2 ? 2000 : t === 10 ? 8000 : 15000); seen.push({ t, labels: (await labels(page)).slice(0, 4) }); await page.screenshot({ path: `${OUT}/run${i}-${t}s.png` }); }
    const r = { i, tapped, seen }; console.log(JSON.stringify(r)); out.push(r);
    if (!seen.at(-1).labels.some((l) => /Where to/.test(l))) { await tap(page, /^Back to home$/, 3000).catch(() => {}); await page.goto(site + `?x=${Date.now()}`); await page.waitForTimeout(9000); await tap(page, /^Back to home$/, 3000).catch(() => {}); }
  }
} finally { save(OUT, "r.json", { out, errors, logs: logs.filter((l) => !/ERR_FAILED/.test(l)) }); await adminCancelActive(); await browser.close(); }
