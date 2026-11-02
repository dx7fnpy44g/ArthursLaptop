// Loads the play app in headless Chromium, mashes keys/mouse through every scene,
// and fails on any page error. Run: node tests/smoke.js (needs `playwright`).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');

(async () => {
  const state = require('fs').mkdtempSync('/tmp/kidos-smoke-');
  require('fs').writeFileSync(path.join(state, 'version'), 'abc123\n');
  const server = spawn('python3', [path.join(__dirname, '..', 'os', 'bin', 'kidos-web')],
    { env: { ...process.env, KIDOS_APPS: path.join(__dirname, '..', 'apps'), KIDOS_STATE: state, KIDOS_RUN: state, KIDOS_PORT: '8791' } });
  await new Promise((r) => setTimeout(r, 800));

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1366, height: 768 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  await page.goto('http://127.0.0.1:8791/');

  const v = await (await page.request.get('http://127.0.0.1:8791/version.json')).json();
  if (v.version !== 'abc123') errors.push('bad version.json ' + JSON.stringify(v));

  for (let scene = 0; scene < 5; scene++) {           // 4 scenes + wrap-around
    for (const k of 'asdfjkl;qwerty 123'.split('')) await page.keyboard.press(k === ' ' ? 'Space' : k);
    for (let i = 0; i < 25; i++) await page.mouse.move(100 + i * 40, 100 + (i % 5) * 120);
    await page.mouse.click(600, 400);
    await page.waitForTimeout(300);
    await page.keyboard.press('Enter');
  }

  // parent chord must POST /api/parent and write the flag file
  for (const c of 'grownup') await page.keyboard.press(c);
  await page.waitForTimeout(500);
  if (!require('fs').existsSync(path.join(state, 'parent-mode'))) errors.push('parent chord did not create flag');
  if (await page.locator('#note').isHidden()) errors.push('parent note not shown');

  await page.screenshot({ path: process.env.SHOT || '/tmp/kidos-smoke.png' });
  await browser.close(); server.kill();
  if (errors.length) { console.error('FAIL:\n' + errors.join('\n')); process.exit(1); }
  console.log('smoke test passed');
})();
