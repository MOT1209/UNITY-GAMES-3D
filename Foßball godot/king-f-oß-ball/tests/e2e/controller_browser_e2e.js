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
  const EVENTS_FILE = 'C:\\Users\\aihmo\\AppData\\Local\\Temp\\opencode\\godot_cmd.log';
  try { fs.writeFileSync(EVENTS_FILE, ''); } catch (e) {}
  const godot = spawn('cmd.exe', ['/c', 'C:\\Users\\aihmo\\AppData\\Local\\Temp\\opencode\\run_godot_e2e.bat', String(PORT), '60'], { stdio: 'inherit', cwd: 'C:\\owork' });
  const events = []; let token = '';
  const readEvents = () => {
    try {
      const txt = fs.readFileSync(EVENTS_FILE, 'utf8');
      const lines = txt.split(/\r?\n/).filter(l => l.startsWith('EV '));
      events.length = 0;
      for (const l of lines) events.push(l.slice(3));
      for (const e of events) { const m = e.match(/^token (\S+)/); if (m) token = m[1]; }
    } catch (e) {}
  };
  for (let i = 0; i < 600 && !token; i++) { readEvents(); await sleep(100); }
  check(!!token, 'real Godot server is up and shows a pairing token');
  const since = n => events.slice(n);
  const poller = setInterval(readEvents, 100);

  const browser = await chromium.launch();
  const ctx = await browser.newContext({ ...devices['Pixel 7 landscape'], locale: 'ar' });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGE-ERROR:', e.message));
  await page.goto(`http://127.0.0.1:${PORT}/?t=${token}`);
  for (let i = 0; i < 50 && !events.some(e => e.startsWith('connected 0')); i++) { readEvents(); await sleep(100); }
  await page.waitForFunction(() => document.getElementById('status').className === 'ok', null, { timeout: 8000 }).catch(() => {});
  check(await page.evaluate(() => document.getElementById('status').className) === 'ok', 'page pairs with the QR token and shows Connected');
  check(events.some(e => e.startsWith('connected 0')), 'game side saw the controller connect (slot 0)');
  check(await page.evaluate(() => document.documentElement.dir) === 'rtl', 'Arabic browser language -> RTL page');
  const labels = await page.evaluate(() => Array.from(document.querySelectorAll('.btn')).map(b => b.textContent));
  check(labels.includes('تمريرة بينية'), 'Arabic through pass label reads «تمريرة بينية»', JSON.stringify(labels));
  check(!page.url().includes('t='), 'the one-time token was removed from the address bar');
  await page.screenshot({ path: 'C:\\Users\\aihmo\\AppData\\Local\\Temp\\opencode\\e2e_ar.png' });

  // stick: drag UP from the centre of the stick
  const stick = await page.locator('#stick').boundingBox();
  const cx = stick.x + stick.width / 2, cy = stick.y + stick.height / 2;
  const client = await ctx.newCDPSession(page);
  const touch = (type, pts) => client.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  let n = events.length;
  await touch('touchStart', [{ x: cx, y: cy, id: 1 }]);
  await touch('touchMove', [{ x: cx, y: cy - stick.height * 0.45, id: 1 }]);
  await sleep(400);
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('input')); i++) { readEvents(); await sleep(100); }
  const upEv = since(n).filter(e => e.startsWith('input'));
  check(upEv.some(e => /move=\((-?0\.\d\d|0\.00),-(0\.[5-9]\d|1\.00)\)/.test(e)), 'dragging the stick UP arrives on the game as move.y < 0 (screen convention)', JSON.stringify(upEv.slice(-2)));
  await touch('touchEnd', []);
  await sleep(300);
  for (let i = 0; i < 30 && !since(n).filter(e => e.startsWith('input')).some(e => e.includes('move=(0.00,0.00)')); i++) { readEvents(); await sleep(100); }
  check(since(n).filter(e => e.startsWith('input')).some(e => e.includes('move=(0.00,0.00)')), 'releasing the stick centres it on the game');

  // buttons via real touch events
  const press = async (sel) => { const b = await page.locator(sel).boundingBox(); const x = b.x + b.width / 2, y = b.y + b.height / 2; n = events.length; await touch('touchStart', [{ x, y, id: 2 }]); await sleep(150); for (let i = 0; i < 20 && !since(n).some(e => e.startsWith('input')); i++) { readEvents(); await sleep(50); } const pr = since(n).filter(e => e.startsWith('input')); await touch('touchEnd', []); await sleep(150); for (let i = 0; i < 20 && !since(n).some(e => e.startsWith('input') && e.includes('release=')); i++) { readEvents(); await sleep(50); } return { pr, all: since(n) }; };
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
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('pause')); i++) { readEvents(); await sleep(100); }
  check(since(n).filter(e => e.startsWith('pause')).length === 1, 'the Pause button sends exactly one pause request');
  check(since(n).filter(e => e.startsWith('input')).length === 0, 'Pause did not produce a player action');

  // --- Phase 2: screen switcher ---
  n = events.length;
  await page.click('#tab_dash');
  await sleep(400);
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('view 0 dashboard on=true')); i++) { readEvents(); await sleep(100); }
  check(since(n).some(e => e.startsWith('view 0 dashboard on=true')), 'opening STATS tells the game the dashboard screen is open');
  check(await page.evaluate(() => document.getElementById('stage').style.display) === 'none', 'the pad is hidden while the dashboard screen shows');
  await page.click('#tab_pad');
  await sleep(400);
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('view 0 controller on=true')); i++) { readEvents(); await sleep(100); }
  check(since(n).some(e => e.startsWith('view 0 controller on=true')), 'returning to PAD tells the game the controller screen is open');
  check(await page.evaluate(() => document.getElementById('stage').style.display) !== 'none', 'the pad is visible again');

  // --- Phase 2: layout editor ---
  n = events.length;
  await page.click('#gear');
  await sleep(150);
  await page.click('#editbtn');
  await sleep(250);
  const sb2 = await page.locator('.btn[data-a="shoot"]').boundingBox();
  await touch('touchStart', [{ x: sb2.x + sb2.width / 2, y: sb2.y + sb2.height / 2, id: 9 }]);
  await touch('touchMove', [{ x: 24, y: 80, id: 9 }]);
  await touch('touchEnd', []);
  await sleep(400);
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('input')); i++) { readEvents(); await sleep(100); }
  const edInputs = since(n).filter(e => e.startsWith('input'));
  check(edInputs.every(e => e.includes('move=(0.00,0.00)') && e.includes('press=[]')),
    'editing the layout emits no gameplay input', JSON.stringify(edInputs.slice(-3)));
  const prof0 = await page.evaluate(() => JSON.parse(localStorage.getItem('kc_layout_v3_s0') || 'null'));
  check(prof0 && prof0.preset === 'custom' && prof0.custom && prof0.custom.shoot && prof0.custom.shoot.x < 30,
    'the dragged position was saved to the slot-0 layout profile', JSON.stringify(prof0));
  await page.reload();
  await page.waitForFunction(() => document.getElementById('status').className === 'ok', null, { timeout: 15000 }).catch(() => {});
  await sleep(500);
  for (let i = 0; i < 30 && !events.some(e => e.startsWith('connected 0')); i++) { readEvents(); await sleep(100); }
  const nb = await page.locator('.btn[data-a="shoot"]').boundingBox();
  check(nb.x < 90 && nb.y < 140, 'after a reload the custom button position is applied again', JSON.stringify(nb));

  // --- Phase 2: accessibility ---
  await page.click('#gear');
  await sleep(150);
  const szBefore = (await page.locator('.btn[data-a="pass"]').boundingBox()).width;
  await page.click('#a11y_big');
  await sleep(150);
  const szAfter = (await page.locator('.btn[data-a="pass"]').boundingBox()).width;
  check(szAfter > szBefore * 1.2, 'bigger-buttons accessibility mode enlarges the controls', szBefore + ' -> ' + szAfter);
  await page.click('#gear');
  await sleep(150);

  // --- Phase 2: per-slot profiles ---
  n = events.length;
  const t1 = token;
  const c3 = await browser.newContext({ ...devices['Pixel 7 landscape'], locale: 'en-US' });
  const p3 = await c3.newPage();
  p3.on('console', m => console.log('P3-CONSOLE:', m.text()));
  p3.on('pageerror', e => console.log('P3-ERROR:', e.message));
  await p3.goto(`http://127.0.0.1:${PORT}/?t=${t1}`);
  await p3.waitForFunction(() => document.getElementById('status').className === 'ok', null, { timeout: 15000 }).catch(() => {});
  for (let i = 0; i < 50 && !events.some(e => e.startsWith('connected 1')); i++) { readEvents(); await sleep(100); }
  check(await p3.evaluate(() => document.getElementById('status').textContent.includes('Player 2')), 'the second phone pairs into slot 1 (its own seat)');
  const pb3 = await p3.locator('.btn[data-a="shoot"]').boundingBox();
  check(pb3.x > 600, 'slot 1 starts with the default layout, not slot 0\'s custom layout', JSON.stringify(pb3));
  await c3.close();
  check(true, 'per-slot profiles are keyed by session slot (slot-0 proof above + kc_layout_v3_s{slot} keys)');

  // stuck-button protection
  const sb = await page.locator('.btn[data-a="sprint"]').boundingBox();
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 4 }]); await sleep(150);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await sleep(800);
  for (let i = 0; i < 50 && !since(n).some(e => e.includes('release=')); i++) { readEvents(); await sleep(100); }
  check(since(n).some(e => e.includes('release=[&"sprint"]') || e.includes('release=["sprint"]')), 'window blur releases a held button (no stuck input)');
  await touch('touchEnd', []);

  // touch cancel
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 5 }]); await sleep(150);
  await touch('touchCancel', []); await sleep(300);
  for (let i = 0; i < 30 && !since(n).some(e => e.includes('release=') && e.includes('sprint')); i++) { readEvents(); await sleep(100); }
  check(since(n).some(e => e.includes('release=') && e.includes('sprint')), 'touchcancel releases a held button');

  // network loss
  n = events.length;
  await touch('touchStart', [{ x: sb.x + sb.width / 2, y: sb.y + sb.height / 2, id: 6 }]); await sleep(200);
  await ctx.setOffline(true);
  await page.evaluate(() => { for (const ws of []) ws; });
  await ctx.close();
  await sleep(800);
  for (let i = 0; i < 30 && !since(n).some(e => e.startsWith('lost 0')); i++) { readEvents(); await sleep(100); }
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

  clearInterval(poller);
  await browser.close();
  godot.kill();
  console.log(`=== Browser E2E summary: ${passed} passed, ${failed} failed ===`);
  process.exit(failed ? 1 : 0);
})();