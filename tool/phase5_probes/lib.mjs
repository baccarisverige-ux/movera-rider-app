// Audit Phase 5 probes (rider web build in Chromium against a local movera-server). Set-up and what each
// script measures: docs/audit/phase-5-screens.md ("How the live build was probed").
import { createRequire } from "node:module";
import { join } from "node:path";
import { writeFileSync, mkdirSync } from "node:fs";
const { chromium } = createRequire(join(process.env.PLAYWRIGHT_ROOT || "/opt/node22/lib/node_modules", "x.js"))("playwright");
export const API = process.env.P5_API || "http://127.0.0.1:8180/api/v1";
export const PICKUP = { latitude: 59.3326, longitude: 18.0649 };
export const DROPOFF = { latitude: 59.3429, longitude: 18.0496 };
const fakeGeo = `(() => {
  window.__geo = window.__geo || { latitude: 59.3326, longitude: 18.0649, accuracy: 8 };
  const pos = () => ({ coords: { latitude: window.__geo.latitude, longitude: window.__geo.longitude, accuracy: 8, altitude: null, altitudeAccuracy: null, heading: null, speed: 0 }, timestamp: Date.now() });
  const watchers = new Map(); let n = 0;
  const geo = { getCurrentPosition(ok) { setTimeout(() => ok(pos()), 50); },
    watchPosition(ok) { const id = ++n; watchers.set(id, setInterval(() => ok(pos()), 1000)); setTimeout(() => ok(pos()), 50); return id; },
    clearWatch(id) { clearInterval(watchers.get(id)); watchers.delete(id); } };
  Object.defineProperty(navigator, "geolocation", { get: () => geo, configurable: true });
})();`;
export async function open({ site, lang = "en", out, canvaskit, width = 390, height = 844, scale }) {
  mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, locale: "en-US", viewport: { width, height }, isMobile: true, hasTouch: true });
  await ctx.addInitScript((l) => { try { localStorage.setItem("flutter.movera_app_language", JSON.stringify(l)); } catch {} 
    try { const n = Number(sessionStorage.getItem("__p5loads") || "0") + 1; sessionStorage.setItem("__p5loads", String(n)); window.__p5load = n; } catch {} }, lang);
  await ctx.addInitScript(fakeGeo);
  await ctx.route(/gstatic\.com\/flutter-canvaskit\/[^/]+\/(.*)$/, (route) => {
    const file = join(canvaskit, route.request().url().replace(/^.*flutter-canvaskit\/[^/]+\//, ""));
    return route.fulfill({ path: file, contentType: file.endsWith(".wasm") ? "application/wasm" : "text/javascript" }).catch(() => route.abort());
  });
  await ctx.route(/maps\.googleapis\.com/, (r) => r.abort());
  await ctx.route("**/api/v1/locations/**", (route) => {
    const req = route.request();
    if (req.method() === "OPTIONS") return route.continue();
    const body = JSON.parse(req.postData() || "{}");
    const json = (o) => route.fulfill({ status: 200, contentType: "application/json", headers: { "access-control-allow-origin": new URL(site).origin }, body: JSON.stringify(o) });
    const url = req.url();
    if (url.endsWith("/autocomplete")) return json({ suggestions: [{ title: "Odenplan", subtitle: "Stockholm", placeId: "p5-odenplan" }] });
    if (url.endsWith("/reverse-geocode")) return json({ address: "Sergels torg, Stockholm", latitude: body.latitude, longitude: body.longitude });
    if (url.endsWith("/geocode")) return /odenplan/i.test(`${body.query} ${body.placeId ?? ""}`)
      ? json({ address: "Odenplan, Stockholm", latitude: DROPOFF.latitude, longitude: DROPOFF.longitude, placeId: "p5-odenplan" })
      : json({ address: "Sergels torg, Stockholm", latitude: PICKUP.latitude, longitude: PICKUP.longitude, placeId: "p5-sergels" });
    return route.continue();
  });
  const page = await ctx.newPage();
  const net = [], errors = [], logs = [];
  page.on("response", async (r) => { if (!r.url().includes("/api/v1/")) return; net.push({ t: Date.now(), call: `${r.request().method()} ${new URL(r.url()).pathname}`, status: r.status() }); });
  page.on("request", (r) => { if (process.env.ALLCONSOLE && /telemetry\/logs/.test(r.url())) { try { for (const e of (JSON.parse(r.postData() || "{}").entries ?? JSON.parse(r.postData() || "{}").logs ?? [])) logs.push(`${Date.now()} T ${e.event ?? e.message ?? ""} ${JSON.stringify(e.extra ?? e.data ?? e.fields ?? "").slice(0, 300)}`); } catch { logs.push("T? " + (r.postData() || "").slice(0, 300)); } } });
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => { if (m.type() === "error" || process.env.ALLCONSOLE) logs.push(`${Date.now()} ${m.type()} ${m.text().slice(0, 400)}`); });
  page.on("framenavigated", (f) => { if (f === page.mainFrame()) logs.push(`NAV ${f.url()}`); });
  return { browser, page, net, errors, logs };
}
export const semantics = (page) => page.evaluate(() => Array.from(document.querySelectorAll("flt-semantics")).map((el) => {
  const own = Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.textContent).join("").trim();
  const r = el.getBoundingClientRect();
  return { label: (el.getAttribute("aria-label") || own || "").replace(/\n/g, " / "), role: el.getAttribute("role") || "", x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width };
}).filter((s) => s.label && s.w > 0));
export const enable = (page) => page.evaluate(() => document.querySelector("flt-semantics-placeholder")?.click());
export async function labels(page) { await enable(page); await page.waitForTimeout(300); return (await semantics(page)).map((s) => s.label); }
export async function tap(page, pattern, timeout = 20000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { await enable(page);
    const hit = (await semantics(page)).find((s) => pattern.test(s.label));
    if (hit) { await page.mouse.click(hit.x, hit.y); return hit.label; }
    await page.waitForTimeout(400); }
  throw new Error(`no ${pattern}`);
}
export async function has(page, pattern, timeout = 15000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { await enable(page); if ((await semantics(page)).some((s) => pattern.test(s.label))) return true; await page.waitForTimeout(400); }
  return false;
}
export const loads = (page) => page.evaluate(() => Number(sessionStorage.getItem("__p5loads") || "0"));
export async function signIn(page, net, site, phone) {
  for (let a = 1; ; a++) { try { return await signInOnce(page, net, site, phone); } catch (e) { if (a >= 4) throw e; console.log('sign-in retry', e.message); } }
}
async function signInOnce(page, net, site, phone) {
  await page.goto(site); await page.waitForTimeout(10000); await enable(page); await page.waitForTimeout(1000);
  const country = (await semantics(page)).find((s) => /Country code/.test(s.label));
  if (country && !/\+46/.test(country.label)) {
    await page.mouse.click(country.x, country.y); await page.waitForTimeout(2000);
    await page.mouse.click(195, 206); await page.waitForTimeout(500);
    await page.keyboard.type("Sweden", { delay: 60 }); await page.waitForTimeout(1500);
    await tap(page, /^Sweden, \+46/); await page.waitForTimeout(1500);
  }
  await enable(page);
  let terms; for (let i = 0; i < 40 && !terms; i++) { terms = (await semantics(page)).find((s) => /terms|villkor|conditions/i.test(s.label)); if (!terms) await page.waitForTimeout(500); }
  await page.mouse.click(250, terms.y - 58); await page.waitForTimeout(600);
  await page.keyboard.type(phone, { delay: 50 }); await page.waitForTimeout(500);
  await page.mouse.click(32, terms.y);
  await tap(page, /^(Continue|Fortsätt|Continuer)$/);
  for (let i = 0; i < 40 && !net.some((c) => /otp\/request/.test(c.call) && c.status === 200); i++) await page.waitForTimeout(500);
  if (!net.some((c) => /otp\/request/.test(c.call) && c.status === 200)) throw new Error('no otp request');
  await page.waitForTimeout(2500);
  await page.mouse.click(54, 630); await page.keyboard.type("1234", { delay: 80 }); await page.waitForTimeout(800);
  await tap(page, /^(Verify|Verifiera|Vérifier)$/, 4000).catch(() => {});
  for (let i = 0; i < 60 && !net.some((c) => /otp\/verify/.test(c.call) && c.status === 200); i++) await page.waitForTimeout(500);
  if (!net.some((c) => /otp\/verify/.test(c.call) && c.status === 200)) throw new Error('no otp verify');
  await page.waitForTimeout(5000);
}
// Driver through the API (the driver app's calls).
async function req(method, path, token, body) {
  const headers = { "content-type": "application/json" }; if (token) headers.authorization = `Bearer ${token}`;
  if (method !== "GET") headers["idempotency-key"] = `p5-${Date.now()}-${Math.random()}`;
  const r = await fetch(API + path, { method, headers, ...(method !== "GET" ? { body: JSON.stringify(body ?? {}) } : {}) });
  const t = await r.text(); return { status: r.status, body: t ? JSON.parse(t) : {} };
}
export async function driver(phone = "+46701740605") {
  const c = await req("POST", "/auth/otp/request", null, { phone, app: "driver" });
  const v = await req("POST", "/auth/otp/verify", null, { phone, sessionId: c.body.sessionId, code: "1234" });
  const tok = v.body.accessToken; let fixAt = Date.now();
  const fix = (p) => ({ lat: p.latitude, lng: p.longitude, accuracy: 5, measuredAt: new Date((fixAt = Math.max(Date.now(), fixAt + 1000))).toISOString() });
  const d = {
    get: (p) => req("GET", p, tok), post: (p, b) => req("POST", p, tok, b),
    async online(at = { latitude: 59.3335, longitude: 18.0655 }) { const prof = (await d.get("/driver/profile")).body; return d.post("/driver/availability", { expectedVersion: prof.version, onlineStatus: "online", location: fix(at) }); },
    async offline() { const prof = (await d.get("/driver/profile")).body; return d.post("/driver/availability", { expectedVersion: prof.version, onlineStatus: "offline" }); },
    move: (at) => d.post("/driver/location", { fixes: [fix(at)] }),
    async acceptAny() { const items = (await d.get("/driver/offers")).body.items ?? []; if (!items.length) return null; const o = items[0]; const r = await d.post(`/offers/${o.offerId}/accept`, { expectedVersion: o.version }); return { ...r, tripId: o.tripId }; },
    async cmd(tripId, path, extra = {}) { const t = (await d.get(`/trips/${tripId}`)).body; return d.post(`/trips/${tripId}/${path}`, { expectedVersion: t.version, ...extra }); },
  };
  return d;
}
export function save(out, name, data) { writeFileSync(join(out, name), JSON.stringify(data, null, 1)); }
let adminTok = null;
export async function adminCancelActive() {
  if (!adminTok) {
    const fs = await import("node:fs");
    const link = fs.readFileSync(process.env.P5_SERVER_LOG || "server.log", "utf8").match(/setupLink":"[^#]*#token=([^"]+)/)[1];
    const pw = "p5 rider local only password";
    await req("POST", "/admin/auth/setup-password", null, { setupToken: link, password: pw });
    adminTok = (await req("POST", "/admin/auth/sign-in", null, { email: process.env.P5_ADMIN_EMAIL || "p5r-admin@example.com", password: pw })).body.accessToken;
  }
  const trips = (await req("GET", "/admin/trips?limit=50", adminTok)).body.items ?? [];
  let n = 0;
  for (const t of trips) if (!/completed|cancel|no_show|expired|ended/.test(t.status)) {
    const full = (await req("GET", `/admin/trips/${t.tripId}`, adminTok)).body;
    const r = await req("POST", `/admin/trips/${t.tripId}/cancel`, adminTok, { expectedVersion: full.version, reasonCode: "admin_other", note: "p5 probe cleanup" }); n += r.status === 200 ? 1 : 0;
  }
  return n;
}
