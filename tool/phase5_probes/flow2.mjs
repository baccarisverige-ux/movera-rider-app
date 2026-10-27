// Ride-time controls on the live build: Share trip, Change route (see new price), Safety Kit, Message, Call,
// Report an issue on the receipt, rating, Schedule for later. Prints labels and API calls after each.
import { open, signIn, labels, tap, has, save, driver, adminCancelActive } from "./lib.mjs";
const S = process.env.P5_DIR || "p5-out";
const OUT = process.env.OUT || S + "/flow2"; const site = process.env.SITE || "http://localhost:7101/";
const { browser, page, net, errors } = await open({ site, out: OUT, canvaskit: process.env.CK || S + "/web-base/canvaskit" });
const d = await driver("+46701740606"); let n = 0;
async function act(name, fn) {
  const m0 = net.length;
  try { await fn(); await page.waitForTimeout(2000); } catch (e) { console.log("ERR", name, e.message); }
  await page.screenshot({ path: `${OUT}/${String(++n).padStart(2, "0")}-${name}.png` });
  console.log(`#${n} ${name} ->`, JSON.stringify((await labels(page)).slice(0, 12)), JSON.stringify(net.slice(m0).filter((c) => !/telemetry|\/rides\/trp_[A-Z0-9]+$|messages/.test(c.call)).map((c) => `${c.status} ${c.call}`)));
}
try {
  await adminCancelActive();
  await signIn(page, net, site, process.env.PHONE || "701740609");
  await tap(page, /^Not now$/, 4000).catch(() => {}); await page.waitForTimeout(1500);
  await act("schedule", () => tap(page, /^Schedule for later$/));
  await act("schedule-back", () => page.evaluate(() => history.back()));
  await tap(page, /^Where to\?/); await page.waitForTimeout(1200);
  await page.mouse.click(160, 146); await page.keyboard.type("Odenplan", { delay: 50 }); await page.waitForTimeout(1200);
  await tap(page, /^Odenplan/); await has(page, /^Select /);
  await act("book-later", () => tap(page, /^Book now or later$/));
  await act("book-later-back", () => page.evaluate(() => history.back()));
  await tap(page, /^Select Movera/); await has(page, /^Confirm and search$/);
  await d.online(); await tap(page, /^Confirm and search$/); await has(page, /^Cancel request$/, 20000);
  await act("finding-safety-kit", () => tap(page, /^Safety Kit$/));
  await act("finding-safety-kit-back", () => page.evaluate(() => history.back()));
  await act("finding-ride-details", () => tap(page, /^Ride details$/));
  await act("finding-ride-details-back", () => page.evaluate(() => history.back()));
  let a = null; for (let i = 0; i < 20 && !a; i++) { a = await d.acceptAny(); if (!a) await page.waitForTimeout(1000); }
  await has(page, /^Cancel ride$/, 20000);
  await act("share", () => tap(page, /^Share trip$/));
  await act("share-back", () => page.evaluate(() => history.back()));
  await act("message", () => tap(page, /^Message$/));
  await act("message-back", () => page.evaluate(() => history.back()));
  await act("call", () => tap(page, /^Call driver$/));
  await act("call-close", () => page.evaluate(() => history.back()));
  await act("more", () => tap(page, /^More options$/));
  await act("more-back", () => page.evaluate(() => history.back()));
  await d.cmd(a.tripId, "head-to-pickup"); await d.move({ latitude: 59.3326, longitude: 18.0649 }); await d.cmd(a.tripId, "arrive"); await page.waitForTimeout(4000);
  await tap(page, /^I'm on the way$/, 4000).catch(() => {});
  await d.cmd(a.tripId, "board"); await d.cmd(a.tripId, "start"); await has(page, /^End trip$/, 20000);
  await act("intrip-back-opens", () => page.evaluate(() => history.back()));
  await act("intrip-see-new-price", () => tap(page, /^See new price$/));
  await act("intrip-close", () => tap(page, /^(Close|Back)$/, 4000));
  await act("intrip-safety-kit", () => tap(page, /^Safety Kit$/));
  await act("intrip-safety-kit-back", () => page.evaluate(() => history.back()));
  await d.cmd(a.tripId, "complete"); await has(page, /^Done$/, 20000);
  await act("done", async () => {});
  await act("report", () => tap(page, /^Report an issue/));
  await act("report-back", () => page.evaluate(() => history.back()));
  await act("rate", () => tap(page, /^Give rating/));
  await act("rate-back", () => page.evaluate(() => history.back()));
  await act("done-tap", () => tap(page, /^Done$/));
  console.log("pageErrors", JSON.stringify(errors));
} finally { await adminCancelActive(); await d.offline().catch(() => {}); await browser.close(); }
