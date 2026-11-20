// Opens the web page in Chromium, scans every tab with axe-core (WCAG 2 A/AA) and fails on serious or critical findings
// or on script errors. Start a static server first: python3 -m http.server 8000 (from the repository root).
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

const base = process.env.WEB_URL || 'http://localhost:8000/';
const browser = await chromium.launch();
let failed = false;
for (const scheme of ['light', 'dark']) {
  const page = await (await browser.newContext({ colorScheme: scheme, viewport: { width: 390, height: 844 } })).newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto(base);
  for (const tab of ['speak', 'book', 'cards', 'learn']) {
    await page.click(`#tabBar [data-go="${tab}"]`);
    await page.waitForTimeout(300);
    const res = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    for (const v of res.violations) {
      const bad = ['serious', 'critical'].includes(v.impact);
      console.log(`${bad ? 'FAIL' : 'warn'} [${scheme}/${tab}] ${v.id} (${v.impact}): ${v.help} x${v.nodes.length}`);
      if (bad) failed = true;
    }
  }
  for (const e of errors) { console.log(`FAIL [${scheme}] script error: ${e}`); failed = true; }
}
await browser.close();
process.exit(failed ? 1 : 0);
