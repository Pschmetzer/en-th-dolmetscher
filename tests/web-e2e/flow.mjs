// End-to-end flow of the web page in Chromium: open a phrase pack, show a card, search, then work offline after the
// service worker has installed. Start a static server first: python3 -m http.server 8000 (from the repository root).
// Exit code 1 on any failed step or script error. Run by .github/workflows/web-a11y.yml (job e2e).
import { chromium } from 'playwright';

const base = process.env.WEB_URL || 'http://localhost:8000/';
const THAI = /[฀-๿]/;
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'allow' });
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
let failed = false;
const step = async (name, fn) => {
  try { await fn(); console.log('ok   ' + name); }
  catch (e) { failed = true; console.log('FAIL ' + name + ': ' + (e && e.message || e)); }
};
const ok = (c, msg) => { if (!c) throw new Error(msg); };

await step('open the page and install the service worker', async () => {
  await page.goto(base);
  await page.evaluate(() => navigator.serviceWorker.ready);
  // the page asks the worker for the packs after start; wait until two packs are in the offline cache
  await page.waitForFunction(async () => {
    const keys = await caches.keys(); let n = 0;
    for (const k of keys) { const c = await caches.open(k); n += (await c.keys()).filter(r => /presets\/(snake-bite-venomous|doctor)\.json$/.test(r.url)).length; }
    return n >= 2;
  }, null, { timeout: 90000, polling: 1000 });
});

await step('open the phrasebook and a pack, review status shown', async () => {
  await page.click('#tabBar [data-go="book"]');
  await page.selectOption('#presetSel', 'snake-bite-venomous');
  await page.waitForFunction(() => document.querySelectorAll('#cards .card').length >= 15);
  const note = await page.textContent('#pbNote');
  ok(/%/.test(note), 'no review status in the pack note: ' + note);
});

await step('show card: tap a card, Thai text in large view', async () => {
  await page.locator('#cards .card').first().click();
  await page.waitForFunction(t => { const el = document.getElementById('partnerText'); return el && t.test(el.textContent); }, THAI, { timeout: 15000 }).catch(() => {});
  const txt = await page.textContent('#partnerText');
  ok(THAI.test(txt), 'no Thai text in the big view: ' + txt);
  await page.keyboard.press('Escape');
});

await step('search inside the pack', async () => {
  const total = await page.locator('#cards .cardwrap:not([hidden])').count();
  await page.fill('#pbQ', 'antivenom');
  await page.waitForTimeout(600);
  const shown = await page.locator('#cards .cardwrap:not([hidden])').count();
  ok(shown >= 1 && shown < total, 'search did not narrow the list: ' + shown + ' of ' + total);
  await page.fill('#pbQ', '');
});

await step('long card link: split into parts, collected, opened', async () => {
  const parts = await page.evaluate(async () => {
    await new Promise((res, rej) => { const el = document.createElement('script'); el.src = 'web-extras.js'; el.onload = res; el.onerror = rej; document.head.appendChild(el); });
    const X = window.DolmetscherExtras, cards = [];
    for (let i = 0; i < 8; i++) cards.push(['Hello number ' + i + ' how are you today', '\u0E2A\u0E27\u0E31\u0E2A\u0E14\u0E35 ' + i]);
    return X.qrParts(location.href.split('#')[0], await X.packEncode({ n: 'Parts', c: cards }), 271);
  });
  ok(parts && parts.length >= 2, 'link was not split');
  for (let i = 0; i < parts.length; i++) {
    const q = await context.newPage();
    await q.goto(parts[i]);
    await q.waitForSelector('#extrasDlg[open]', { timeout: 15000 });
    const txt = await q.textContent('#extrasDlg .x24body');
    if (i < parts.length - 1) ok(/\d/.test(txt) && !/Parts/.test(txt), 'part ' + (i + 1) + ' should only be stored: ' + txt.slice(0, 60));
    else ok(/Parts/.test(txt), 'pack did not open after the last part: ' + txt.slice(0, 60));
    await q.close();
  }
});

await step('offline reload: phrasebook still works', async () => {
  await context.setOffline(true);
  await page.reload();
  await page.click('#tabBar [data-go="book"]');
  await page.selectOption('#presetSel', 'doctor');
  await page.waitForFunction(() => document.querySelectorAll('#cards .card').length >= 5, null, { timeout: 30000 });
  const msg = await page.textContent('#pbMsg');
  ok(!msg.trim(), 'phrasebook message while offline: ' + msg);
});

await step('no script errors', async () => { ok(errors.length === 0, errors.join(' | ')); });

await browser.close();
process.exit(failed ? 1 : 0);
