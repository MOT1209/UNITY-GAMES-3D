// KING CONTROLLER: browser end-to-end check. EMULATED mobile Chromium (Playwright, touch + landscape viewport)
// against the REAL Godot KingControllerServer. This is NOT a real Android phone: it proves the page JavaScript,
// the wire protocol and the server work together in a real browser engine; Wi-Fi, a real touchscreen, a real
// phone browser and the Windows firewall are NOT covered (see docs/qa/KING_CONTROLLER_QA.md).
//   node tests/e2e/controller_browser_e2e.js
const { chromium, devices } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const PORT = 17500;
let passed = 0, failed = 0;
const check = (ok, name, detail = '') => { if (ok) { passed++; console.log('[PASS] ' + name); } else { failed++; console.log('[FAIL] ' + name + (detail ? ' - ' + detail : '')); } };
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const godot = spawn(process.env.GODOT || 'godot', ['--headless', '--path', '.', '--script', 'tests/e2e/serve_controller.gd', '--', String(PORT), '60'], { stdio: ['ignore', 'pipe', 'pipe'] });
  const events = []; let token = '';
  godot.stdout.on('data', d => String(d).split('\n').forEach(l => { if (l.startsWith('EV ')) { events.push(l.slice(3)); const m = l.match(/EV token (\S+)/); if (m) token = m[1]; } }));
  for (let i = 0; i < 100 && !token; i++) await sleep(100);
  check(!!token, 'real Godot server is up and shows a pairing token');
  const since = n => events.slice(n);
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ ...devices['Pixel 7 landscape'], locale: 'ar' });
  const page = await ctx.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/?t=${token}`);
  await page.waitForFunction(() => document.getElementById('status').className === 'ok', null, { timeout: 8000 }).catch(() => {});
  check(await page.evaluate(() => document.getElementById('status').className) === 'ok', 'page pairs with the QR token and shows Connected');
  check(events.some(e => e.startsWith('connected 0')), 'game side saw the controller connect (slot 0)');
  check(await page.evaluate(() => document.documentElement.dir) === 'rtl', 'Arabic browser language -> RTL page');
  const labels = await page.evaluate(() => Array.from(document.querySelectorAll('.btn')).map(b => b.textContent));
  check(labels.includes('تمريرة بينية'), 'Arabic through pass label reads «تمريرة بينية»', JSON.stringify(labels));
  check(!page.url().includes('t='), 'the one-time token was removed from the address bar');
  await page.screenshot({ path: '/tmp/claude-0/evidence/e2e_ar.png' });

  // stick: drag UP from the centre of the stick
  const stick = await page.locator('#stick').boundingBox();
  const cx = stick.x + stick.width / 2, cy = stick.y + stick.height / 2;
  const client = await ctx.newCDPSession(page);
  const touch = (type, pts) => client.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  let n = events.length;
  await touch('touchStart', [{ x: cx, y: cy, id: 1 }]);
  await touch('touchMove', [{ x: cx, y: cy - stick.height * 0.45, id: 1 }]);
  await sleep(400);
  const upEv = since(n).filter(e => e.startsWith('input'));
  check(upEv.some(e => /move=\((-?0\.\d\d|0\.00),-(0\.[5-9]\d|1\.00)\)/.test(e)), 'dragging the stick UP arrives on the game as move.y < 0 (screen convention)', JSON.stringify(upEv.slice(-2)));
  await touch('touchEnd', []);
  await sleep(300);
  check(since(n).filter(e => e.startsWith('input')).slice(-1)[0].includes('move=(0.00,0.00)'), 'releasing the stick centres it on the game');

  // buttons via real touch events
  const press = async (sel) => { const b = await page.locator(sel).boundingBox(); const x = b.x + b.width / 2, y = b.y + b.height / 2; n = events.length; await touch('touchStart', [{ x, y, id: 2 }]); await sleep(150); const pr = since(n).filter(e => e.startsWith('input')); await touch('touchEnd', []); await sleep(150); return { pr, all: since(n) }; };
  for (const a of ['sprint', 'tackle', 'switch_player', 'cross', 'lob_pass', 'through_pass', 'pass', 'shoot']) {
    const r = await press(`.btn[data-a="${a}"]`);
    check(r.pr.some(e => e.includes(`press=["${a}"]`) || e.includes(`press=[&"${a}"]`)), `touching "${a}" presses it in the game`, JSON.stringify(r.all));
    check(r.all.some(e => e.startsWith('input') && (e.includes(`release=[&"${a}"]`) || e.includes(`release=["${a}"]`))), `lifting the finger releases "${a}"`);
  }
  // Pause
  n = events.length;
  const pb = await page.locator('#pause').boundingBox();
  await touch('touchStart', [{ x: pb.x + pb.width / 2, y: pb.y + pb.height / 2, id: 3 }]); await sleep(50); await touch('touchEnd', []);
  await sleep(500);
  check(since(n).filter(e => e.startsWith('pause')).length === 1, 'the Pause button sends exactly one pause request');
  check(since(n).filter(e => e.startsWith('input')).length === 0, 'Pause did not produce a player action');

  // stuck-button protection: hold sprint, then the page loses visibility / blur
  const sb = await page.locator('.btn[data-a="sprint"]').boundingBox();
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 4 }]); await sleep(150);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await sleep(300);
  check(since(n).some(e => e.includes('release=[&"sprint"]') || e.includes('release=["sprint"]')), 'window blur releases a held button (no stuck input)');
  await touch('touchEnd', []);

  // touch cancel
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 5 }]); await sleep(150);
  await touch('touchCancel', []); await sleep(300);
  check(since(n).some(e => e.includes('release=') && e.includes('sprint')), 'touchcancel releases a held button');

  // sudden network loss while holding: server must release everything
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 6 }]); await sleep(200);
  await ctx.setOffline(true);
  await page.evaluate(() => { for (const ws of []) ws; });
  await ctx.close();   // closes the socket abruptly
  await sleep(800);
  check(since(n).some(e => e.startsWith('lost 0')), 'closing the page while holding a button is noticed by the game (lost)');
  check(since(n).some(e => e.startsWith('input') && e.includes('release=') && e.includes('sprint')), 'and the held sprint is released on the game side');

  // English / German
  for (const [loc, expect] of [['en-US', 'THROUGH'], ['de-DE', 'STEILPASS']]) {
    const c2 = await browser.newContext({ ...devices['Pixel 7 landscape'], locale: loc });
    const p2 = await c2.newPage();
    await p2.goto(`http://127.0.0.1:${PORT}/?t=ZZZZZZZZ`);
    await sleep(500);
    const l2 = await p2.evaluate(() => Array.from(document.querySelectorAll('.btn')).map(b => b.textContent));
    check(l2.includes(expect) && await p2.evaluate(() => document.documentElement.dir) === 'ltr', `${loc}: labels and LTR (${expect})`);
    await c2.close();
  }
  await browser.close();
  godot.kill();
  console.log(`=== Browser E2E summary: ${passed} passed, ${failed} failed ===`);
  process.exit(failed ? 1 : 0);
})();
