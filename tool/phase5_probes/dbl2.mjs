// "Select Movera" tapped twice: does the second tap land on Set pickup's "Confirm and search" and book?
import { open, signIn, labels, tap, has, semantics, enable, adminCancelActive } from "./lib.mjs";
const S = process.env.P5_DIR || "p5-out";
const OUT = process.env.OUT || S + "/dbl2"; const site = process.env.SITE || "http://localhost:7101/";
const { browser, page, net, errors } = await open({ site, out: OUT, canvaskit: process.env.CK || S + "/web-base/canvaskit" });
const gaps = (process.env.GAPS || "80,200,350,600").split(",").map(Number);
const res = [];
try {
  await adminCancelActive();
  await signIn(page, net, site, process.env.PHONE || "701740610");
  for (const gap of gaps) {
    await page.goto(site + `?g=${gap}-${Date.now()}`); await page.waitForTimeout(9000);
    await tap(page, /^Not now$/, 2000).catch(() => {}); await tap(page, /^Back to home$/, 2000).catch(() => {});
    await tap(page, /^Where to\?/); await page.waitForTimeout(1200);
    await page.mouse.click(160, 146); await page.keyboard.type("Odenplan", { delay: 50 }); await page.waitForTimeout(1200);
    await tap(page, /^Odenplan/); await has(page, /^Select Movera/); await page.waitForTimeout(2500);
    await enable(page); const hit = (await semantics(page)).find((s) => /^Select Movera/.test(s.label));
    const m = net.length;
    await page.mouse.click(hit.x, hit.y); await page.waitForTimeout(gap); await page.mouse.click(hit.x, hit.y);
    await page.waitForTimeout(4000);
    const r = { gap, at: [Math.round(hit.x), Math.round(hit.y)], trips: net.slice(m).filter((c) => /^POST \/api\/v1\/trips$/.test(c.call)).length, screen: (await labels(page)).slice(0, 3) };
    console.log(JSON.stringify(r)); res.push(r);
    await page.screenshot({ path: `${OUT}/gap-${gap}.png` });
    await adminCancelActive();
  }
  console.log("pageErrors", JSON.stringify(errors));
} finally { await adminCancelActive(); await browser.close(); }
