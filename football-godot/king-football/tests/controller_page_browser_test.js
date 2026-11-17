// Browser test of the phone page's control preferences (layout, profiles, persistence, haptics).
// Needs Node + Playwright (not part of run_all.sh, which is Godot-only):
//   node tests/controller_page_browser_test.js
// The WebSocket is NOT reached (no game running), so this tests the page's own behaviour only.
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'assets', 'controller', 'controller_page.html'), 'utf8').replace('__WS_PORT__', '1');
let pass = 0, fail = 0;
const check = (ok, name, d) => { if (ok) { pass++; console.log('[PASS] ' + name); } else { fail++; console.log('[FAIL] ' + name + (d ? ' — ' + d : '')); } };

(async () => {
  const srv = http.createServer((q, r) => { r.writeHead(200, {'content-type': 'text/html'}); r.end(html); }).listen(0);
  const url = 'http://127.0.0.1:' + srv.address().port + '/?lang=en';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 800, height: 380 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  await page.addInitScript(() => { document.addEventListener('DOMContentLoaded', () => { const st = document.createElement('style'); st.textContent = '#overlay,#rotate{display:none!important}'; document.head.appendChild(st); }); window.__vib = []; navigator.vibrate = (p) => { window.__vib.push(p); return true; }; });
  await page.goto(url);
  const box = async sel => page.locator(sel).first().boundingBox();

  check(errors.length === 0, 'page loads without script errors', errors.join('|'));
  let st = await box('#stick'), bt = await box('#btns');
  check(st.x < bt.x, 'default: stick on the left, buttons on the right');

  await page.click('#gear');
  await page.click('#ctl .chips button[data-id="left"]');
  st = await box('#stick'); bt = await box('#btns');
  check(st.x > bt.x, 'left-handed: stick on the right, buttons on the left');

  await page.fill('#pref_size', '1.3').catch(() => {});
  await page.evaluate(() => { const i = document.getElementById('pref_size'); i.value = '1.3'; i.dispatchEvent(new Event('input')); });
  const big = await box('.btn.big');
  await page.evaluate(() => { const i = document.getElementById('pref_size'); i.value = '0.7'; i.dispatchEvent(new Event('input')); });
  const small = await box('.btn.big');
  check(big.width > small.width * 1.5, 'button size slider resizes the buttons', big.width + ' vs ' + small.width);

  await page.evaluate(() => { const i = document.getElementById('pref_opac'); i.value = '0.5'; i.dispatchEvent(new Event('input')); });
  check(await page.evaluate(() => getComputedStyle(document.getElementById('btns')).opacity) === '0.5', 'opacity slider applies');

  await page.click('#ctl .chips button[data-id="tackle"]');
  check(await page.evaluate(() => document.querySelector('.btn[data-a="tackle"]').classList.contains('hidden')), 'a button can be hidden');
  check(await page.evaluate(() => !document.querySelector('.btn[data-a="pass"]').classList.contains('hidden')), 'PASS stays visible (cannot be hidden)');
  check(await page.locator('#ctl .chips button[data-id="pass"]').count() === 0 && await page.locator('#ctl .chips button[data-id="shoot"]').count() === 0, 'PASS / SHOOT are not offered for hiding');

  // persistence across reload
  await page.reload();
  const prefs = await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')));
  check(prefs.hand === 'left' && prefs.hidden.includes('tackle') && prefs.opac === 0.5, 'settings persist in localStorage', JSON.stringify(prefs));
  st = await box('#stick'); bt = await box('#btns');
  check(st.x > bt.x, 'left-handed layout is restored after reload');

  // profiles
  await page.click('#gear');
  await page.selectOption('#profsel', '2');
  await page.click('#profsave');
  await page.click('#profreset');
  check(await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')).hand) === 'right', 'reset returns to defaults');
  await page.click('#profload');
  check(await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')).hand) === 'left', 'profile 2 loads the saved layout');
  await page.selectOption('#profsel', '3');
  await page.click('#profload');
  check(await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')).hand) === 'left', 'loading an empty profile changes nothing');
  await page.click('#ctl .chips button[data-id="pdef"]');
  check(await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')).hand) === 'right', 'preset Default');
  await page.click('#ctl .chips button[data-id="pbig"]');
  check(await page.evaluate(() => JSON.parse(localStorage.getItem('kc_prefs')).size) === 1.3, 'preset Big buttons');

  // corrupt / out-of-range storage is sanitised
  await page.evaluate(() => localStorage.setItem('kc_prefs', JSON.stringify({hand: 'up', size: 99, dz: -5, sens: 'x', hidden: ['pass', 'tackle', 'zzz'], hap: 'huge'})));
  await page.reload();
  const clean = await page.evaluate(() => { try { return prefs; } catch (e) { return null; } });
  check(clean && clean.hand === 'right' && clean.size === 1.4 && clean.dz === 0.04 && clean.sens === 1 &&
        JSON.stringify(clean.hidden) === '["tackle"]' && clean.hap === 'light', 'corrupt saved settings are clamped / dropped', JSON.stringify(clean));

  // haptics
  await page.evaluate(() => localStorage.setItem('kc_prefs', JSON.stringify({hap: 'strong'})));
  await page.reload();
  await page.evaluate(() => { window.__vib.length = 0; });
  const pb = await box('.btn[data-a="pass"]');
  await page.mouse.move(pb.x + pb.width / 2, pb.y + pb.height / 2);
  await page.mouse.down(); await page.mouse.up();
  check((await page.evaluate(() => window.__vib)).length >= 1 && (await page.evaluate(() => window.__vib[0])) === 22, 'strong haptics vibrate 22 ms on a button press');
  await page.evaluate(() => { localStorage.setItem('kc_prefs', JSON.stringify({hap: 'off'})); });
  await page.reload();
  await page.evaluate(() => { window.__vib.length = 0; });
  await page.mouse.move(pb.x + pb.width / 2, pb.y + pb.height / 2); await page.mouse.down(); await page.mouse.up();
  check((await page.evaluate(() => window.__vib)).length === 0, 'haptics off: no vibration');

  // unsupported device: no crash, label says so
  const ctx2 = await browser.newContext({ viewport: { width: 800, height: 380 } });
  const p2 = await ctx2.newPage();
  const e2 = []; p2.on('pageerror', e => e2.push(String(e)));
  await p2.addInitScript(() => { document.addEventListener('DOMContentLoaded', () => { const st = document.createElement('style'); st.textContent = '#overlay,#rotate{display:none!important}'; document.head.appendChild(st); }); Object.defineProperty(navigator, 'vibrate', { value: undefined, configurable: true }); });
  await p2.goto(url);
  await p2.click('#gear');
  check(e2.length === 0 && (await p2.locator('#ctl').innerText()).includes('Not supported'), 'no vibration API: page works and says it is unsupported', e2.join('|'));

  // languages
  for (const [l, word] of [['de', 'Steuerung'], ['ar', 'التحكم']]) {
    await p2.goto(url.replace('lang=en', 'lang=' + l)); await p2.click('#gear');
    check((await p2.locator('#ctl').innerText()).includes(word), 'controls are translated: ' + l);
  }
  console.log('=== Browser test summary: ' + pass + ' passed, ' + fail + ' failed ===');
  await browser.close(); srv.close();
  process.exit(fail ? 1 : 0);
})();
