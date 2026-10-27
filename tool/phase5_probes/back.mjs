// N3 probe: reach each booking step, press Back (browser history back, then the in-app Back/Close), and record
// where the app lands, whether the page reloaded (sessionStorage load counter) and any page error.
import { open, signIn, labels, tap, has, loads, save, driver, adminCancelActive } from "./lib.mjs";
const S = process.env.P5_DIR || "p5-out";
const OUT = process.env.OUT || S + "/back"; const site = process.env.SITE || "http://localhost:7101/";
const CK = process.env.CK || S + "/web-base/canvaskit";
const { browser, page, net, errors, logs } = await open({ site, out: OUT, canvaskit: CK });
const d = await driver();
let trip = null;
const steps = [
  ["plan", async () => { await tap(page, /^Where to\?/); }],
  ["plan-typed", async () => { await page.mouse.click(160, 146); await page.keyboard.type("Odenplan", { delay: 50 }); await page.waitForTimeout(1200); }],
  ["select", async () => { await tap(page, /^Odenplan/); await has(page, /^Select /, 15000); }],
  ["pickup", async () => { await tap(page, /^Select Movera/); await has(page, /^Confirm and search$/, 15000); }],
  ["finding", async () => { await d.online(); await tap(page, /^Confirm and search$/); await has(page, /^Cancel request$/, 20000); }],
  ["waiting", async () => { let a = null; for (let i = 0; i < 20 && !a; i++) { a = await d.acceptAny(); if (!a) await page.waitForTimeout(1000); } trip = a.tripId; await has(page, /^Cancel ride$/, 20000); }],
  ["arrived", async () => { await d.cmd(trip, "head-to-pickup"); await d.move({ latitude: 59.3326, longitude: 18.0649 }); await d.cmd(trip, "arrive"); await page.waitForTimeout(5000); }],
  ["intrip", async () => { await tap(page, /^I'm on the way$/, 4000).catch(() => {}); await d.cmd(trip, "board"); await d.cmd(trip, "start"); await has(page, /^End trip$/, 20000); }],
  ["done", async () => { await d.cmd(trip, "complete"); await has(page, /^Done$/, 20000); }],
];
async function home() {
  await adminCancelActive(); await d.offline().catch(() => {});
  await page.goto(site + `?p5=${Date.now()}`); await page.waitForTimeout(9000);
  await tap(page, /^Not now$/, 3000).catch(() => {});
  await tap(page, /^Done$/, 2000).catch(() => {});
  await tap(page, /^Back to home$/, 3000).catch(() => {}); await page.waitForTimeout(1500);
  if (!(await has(page, /^Where to\?/, 15000))) throw new Error("not home at start");
}
const results = [];
const only = process.env.ONLY ? process.env.ONLY.split(",") : null;
const methods = (process.env.METHODS || "browser,app").split(",");
try {
  await signIn(page, net, site, "701740608");
  for (let k = 0; k < steps.length; k++) {
    if (only && !only.includes(steps[k][0])) continue;
    for (const method of methods) {
      try {
        await home(); trip = null;
        for (let j = 0; j <= k; j++) await steps[j][1]();
        await page.waitForTimeout(1500);
        const name = `${String(k + 1).padStart(2, "0")}-${steps[k][0]}-${method}`;
        const before = await labels(page); const l0 = await loads(page); const e0 = errors.length; const url0 = page.url();
        await page.screenshot({ path: `${OUT}/${name}-a.png` });
        let did = "";
        if (method === "browser") { did = "history.back()"; await page.evaluate(() => history.back()); }
        else if (method === "reload") { did = "page.reload()"; await page.reload(); await page.waitForTimeout(9000); }
        else { did = await tap(page, /^(Back|Close)$/, 2000).catch(() => "no in-app Back/Close"); }
        await page.waitForTimeout(4000);
        let l1 = -1; try { l1 = await loads(page); } catch { }
        const after = await labels(page).catch(() => []);
        await page.screenshot({ path: `${OUT}/${name}-b.png` });
        const r = { step: steps[k][0], method, did, urlBefore: url0, urlAfter: page.url(), reloaded: l1 !== l0, onHome: after.some((s) => /^Where to\?/.test(s)), before: before.slice(0, 6), after: after.slice(0, 8), pageErrors: errors.slice(e0) };
        console.log(JSON.stringify(r)); results.push(r);
      } catch (e) { console.log("ERR", steps[k][0], method, e.message); results.push({ step: steps[k][0], method, error: e.message }); await page.screenshot({ path: `${OUT}/err-${steps[k][0]}-${method}.png` }); }
    }
  }
} finally {
  save(OUT, "back.json", { results, offContract: net.filter((c) => c.status === 404), errors, logs: logs.filter((l) => !/ERR_FAILED/.test(l)) });
  await adminCancelActive(); await d.offline().catch(() => {}); await browser.close();
}
