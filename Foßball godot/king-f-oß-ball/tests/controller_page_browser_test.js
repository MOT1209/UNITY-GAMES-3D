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
  // ---- match feed: fake WebSocket that pairs and lets the test push PC messages ----
  const ctx3 = await browser.newContext({ viewport: { width: 800, height: 380 }, hasTouch: true });
  const p3 = await ctx3.newPage();
  const e3 = []; p3.on('pageerror', e => e3.push(String(e)));
  await p3.addInitScript(() => {
    document.addEventListener('DOMContentLoaded', () => { const st = document.createElement('style'); st.textContent = '#overlay,#rotate{display:none!important}'; document.head.appendChild(st); });
    window.__vib = []; navigator.vibrate = p => { window.__vib.push(p); return true; };
    window.__sent = [];
    window.WebSocket = class { constructor() { window.__ws = this; this.readyState = 1; setTimeout(() => { this.onopen && this.onopen(); }, 0); }
      send(t) { window.__sent.push(JSON.parse(t)); const m = JSON.parse(t);
        if (m.type === 'pair' || m.type === 'resume') setTimeout(() => this.onmessage({data: JSON.stringify({v: 2, type: 'paired', slot: 0, session: 'a'.repeat(32), tick_rate: 30})}), 0); }
      close() { this.readyState = 3; } };
    window.__push = o => window.__ws.onmessage({data: JSON.stringify(o)});
  });
  await p3.goto(url.replace('?lang=en', '?lang=en&t=ABCDEFGH'));
  await p3.waitForFunction(() => document.getElementById('status').textContent.startsWith('Connected'));
  await p3.click('#dashbtn');
  check((await p3.locator('#dempty').innerText()).includes('Waiting'), 'dashboard before any data says it is waiting (shows nothing invented)');
  const frame = { v: 2, type: 'state', you: 'home', clock: '12:34', half: 1, phase: 1, score: [2, 1], poss: [60, 40], shots: [7, 3], sot: [4, 1],
                  cards: [1, 0, 2, 1], ball: [0.1, 0.2], me: [0, -0.9, -0.3, -0.4], opp: [0.2, 0.5] };
  await p3.evaluate(f => window.__push(f), frame);
  check((await p3.locator('#dscore').innerText()) === '2 - 1', 'dashboard shows the PC score');
  const dtxt = await p3.locator('#dcol').innerText();
  check(dtxt.includes('60%') && dtxt.includes('7 (4)') && dtxt.includes('12:34'), 'possession, shots and clock come from the frame', dtxt.replace(/\n/g, '|'));
  const px = await p3.evaluate(() => { const c = document.getElementById('dmap'), g = c.getContext('2d'); const d = g.getImageData(0, 0, c.width, c.height).data;
    let gold = 0, red = 0; for (let i = 0; i < d.length; i += 4) { if (d[i] > 190 && d[i+1] > 150 && d[i+2] < 90) gold++; if (d[i] > 160 && d[i+1] < 70 && d[i+2] < 80) red++; } return {gold, red}; });
  check(px.gold > 20 && px.red > 5, 'mini-map draws own (gold) and opposing (red) players from the frame', JSON.stringify(px));
  await p3.evaluate(() => { window.__vib.length = 0; });
  await p3.evaluate(() => window.__push({ v: 2, type: 'event', kind: 'goal', id: 5, minute: 31.2, mine: true, player: '<b>Ali</b>', own_goal: false }));
  check((await p3.evaluate(() => window.__vib)).length === 1 && Array.isArray((await p3.evaluate(() => window.__vib))[0]), 'a goal for you vibrates with a pattern');
  const feedHtml = await p3.locator('#dfeed').innerHTML();
  check(feedHtml.includes('&lt;b&gt;Ali') && !feedHtml.includes('<b>'), 'player names are inserted as text, never as HTML');
  check((await p3.locator('#dfeed').innerText()).includes("31' Goal"), 'the event feed lists the goal with its minute');
  await p3.evaluate(() => { window.__vib.length = 0; window.__push({ v: 2, type: 'event', kind: 'goal', id: 6, minute: 40, mine: false, player: 'X', own_goal: false }); });
  const conc = await p3.evaluate(() => window.__vib);
  check(conc.length === 1 && conc[0] !== undefined, 'a goal against vibrates too (different pattern)');
  await p3.evaluate(() => { window.__vib.length = 0; window.__push({ v: 2, type: 'event', kind: 'red_card', id: 7, minute: 41, mine: true, player: 'Y' }); });
  check((await p3.evaluate(() => window.__vib)).length === 1, 'a red card vibrates');
  await p3.evaluate(() => localStorage.setItem('kc_prefs', JSON.stringify({hap: 'off'})));
  await p3.reload();
  await p3.waitForFunction(() => document.getElementById('status').textContent.startsWith('Connected'));
  await p3.evaluate(() => { window.__vib.length = 0; window.__push({ v: 2, type: 'event', kind: 'goal', id: 1, minute: 1, mine: true, player: 'Z', own_goal: false }); });
  check((await p3.evaluate(() => window.__vib)).length === 0, 'vibration off: no goal vibration');
  await p3.evaluate(() => window.__push({ v: 2, type: 'state', score: 'junk', me: 'x', opp: [1e999, null], ball: {}, cards: 5 }));
  check(e3.length === 0, 'junk feed data does not crash the page', e3.join('|'));
  check(!(await p3.evaluate(() => window.__sent.some(m => m.type === 'state' || m.type === 'event'))), 'the page never sends feed messages back to the PC');
  // click-through: the dashboard must not block the controls
  await p3.click('#dashbtn');
  const passBox = await p3.locator('.btn[data-a="pass"]').boundingBox();
  const hit = await p3.evaluate(([x, y]) => document.elementFromPoint(x, y).closest('.btn') ? document.elementFromPoint(x, y).closest('.btn').dataset.a : (document.elementFromPoint(x, y).id || document.elementFromPoint(x, y).tagName), [passBox.x + passBox.width / 2, passBox.y + passBox.height / 2]);
  check(hit === 'pass', 'with the dashboard open the PASS button is still the touched element', hit);
  console.log('=== Browser test summary: ' + pass + ' passed, ' + fail + ' failed ===');
  await browser.close(); srv.close();
  process.exit(fail ? 1 : 0);
})();
