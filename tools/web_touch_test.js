// Usage: build the web version (godot --headless --export-release "Web" build/web/index.html),
// serve build/web on port 8765 (python3 -m http.server 8765), then:
//   node tools/web_touch_test.js '[{"wait":35000},{"tap":[430,204]},{"wait":2000,"shot":"out.png"}]'
// Coordinates are CSS pixels on an emulated Pixel 7 held sideways (863 x 360).
// Drives the web build like a phone: taps, drags and pinches, with screenshots.
const { chromium, devices } = require('playwright');
const steps = JSON.parse(process.argv[2]);
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ ...devices['Pixel 7 landscape'] });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', m => { if (/SCRIPT|ERROR|error/i.test(m.text()) && !/MSAA|texture_storage/.test(m.text())) logs.push(m.text()); });
  page.on('pageerror', e => logs.push('pageerror: ' + e.message));
  await page.goto('http://127.0.0.1:8765/index.html');
  const cdp = await ctx.newCDPSession(page);
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((p, i) => ({ x: p[0], y: p[1], id: i })) });
  for (const s of steps) {
    if (s.wait) await page.waitForTimeout(s.wait);
    if (s.tap) await page.touchscreen.tap(s.tap[0], s.tap[1]);
    if (s.drag) { // one finger from a to b
      const [a, b] = s.drag; await touch('touchStart', [a]);
      for (let k = 1; k <= 10; k++) { await touch('touchMove', [[a[0] + (b[0] - a[0]) * k / 10, a[1] + (b[1] - a[1]) * k / 10]]); await page.waitForTimeout(30); }
      if (s.hold_shot) await page.screenshot({ path: s.hold_shot });
      await touch('touchEnd', []);
    }
    if (s.pinch) { // two fingers moving apart (zoom in) or together
      const [c, d0, d1] = s.pinch; await touch('touchStart', [[c[0] - d0, c[1]], [c[0] + d0, c[1]]]);
      for (let k = 1; k <= 10; k++) { const d = d0 + (d1 - d0) * k / 10; await touch('touchMove', [[c[0] - d, c[1]], [c[0] + d, c[1]]]); await page.waitForTimeout(30); }
      await touch('touchEnd', []);
    }
    if (s.shot) await page.screenshot({ path: s.shot });
  }
  console.log(logs.slice(-15).join('\n') || 'no errors');
  await browser.close();
})();
