// Visits every side-menu / account entry on the live build and records labels, API calls (404 = not served) and Back.
import { open, signIn, labels, tap, has, loads, save } from "./lib.mjs";
const S = process.env.P5_DIR || "p5-out";
const OUT = process.env.OUT || S + "/menu"; const site = process.env.SITE || "http://localhost:7101/";
const { browser, page, net, errors, logs } = await open({ site, out: OUT, canvaskit: process.env.CK || S + "/web-base/canvaskit", });
const res = [];
const depth2 = process.env.DEPTH2 === "1";
try {
  await signIn(page, net, site, process.env.PHONE || "701740609"); if (process.env.H) await page.setViewportSize({ width: 390, height: Number(process.env.H) });
  await tap(page, /^Not now$/, 5000).catch(() => {}); await page.waitForTimeout(2000);
  await tap(page, /^Menu$/); await page.waitForTimeout(2000);
  const menu = await labels(page); console.log("MENU", JSON.stringify(menu));
  await page.screenshot({ path: `${OUT}/menu.png` });
  const entries = menu.filter((l) => !/^(Menu|Close|Back)$/.test(l));
  for (const [i, entry] of entries.entries()) {
    const n0 = net.length, e0 = errors.length;
    try {
      await page.goto(site + `?m=${i}`); await page.waitForTimeout(8000);
      await tap(page, /^Not now$/, 2000).catch(() => {});
      await tap(page, /^Menu$/); await page.waitForTimeout(1500);
      await tap(page, new RegExp("^" + entry.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$"), 5000);
      await page.waitForTimeout(3500);
      const l = await labels(page);
      await page.screenshot({ path: `${OUT}/m${String(i).padStart(2, "0")}.png` });
      const sub = [];
      if (depth2 && (!process.env.SUBFOR || new RegExp(process.env.SUBFOR).test(entry))) for (const s of l) { if (/^(Back|Close|Menu|Sign out|Delete account)$/i.test(s)) continue;
        const m0 = net.length;
        try { await tap(page, new RegExp("^" + s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$"), 3000); await page.waitForTimeout(3000);
          const sl = await labels(page); await page.screenshot({ path: `${OUT}/m${String(i).padStart(2, "0")}-${sub.length}.png` });
          sub.push({ s, labels: sl.slice(0, 12), calls: net.slice(m0).filter((c) => !/telemetry/.test(c.call)).map((c) => `${c.status} ${c.call}`) });
          await page.evaluate(() => history.back()); await page.waitForTimeout(2000);
          if (!(await labels(page)).includes(l[1])) { await page.evaluate(() => history.back()); await page.waitForTimeout(2000); }
        } catch (e) { sub.push({ s, error: e.message }); } }
      const l0 = await loads(page);
      await page.evaluate(() => history.back()); await page.waitForTimeout(2500);
      const after = await labels(page);
      const r = { entry, labels: l, sub, calls: net.slice(n0).filter((c) => !/telemetry/.test(c.call)).map((c) => `${c.status} ${c.call}`), backReloaded: (await loads(page)) !== l0, afterBack: after.slice(0, 3), pageErrors: errors.slice(e0) };
      console.log(JSON.stringify(r)); res.push(r);
    } catch (e) { console.log("ERR", entry, e.message); res.push({ entry, error: e.message }); }
  }
} finally { save(OUT, "menu.json", { res, notFound: net.filter((c) => c.status === 404), errors }); await browser.close(); }
