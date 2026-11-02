// Web audio check: is sound actually audible in the browser build?
//   node tools/web_audio_check.js http://127.0.0.1:8080/index.html
// Loads the page in headless Chromium (autoplay allowed, so the menu music starts without a tap),
// puts an AnalyserNode in front of the speakers and fails unless a real signal comes out.
// Catches the class of bug where Godot "plays" sounds that never reach the output (e.g. buses that
// were added at run time, which the web build does not route).
const { chromium, devices } = require('playwright');
const URL = process.argv[2] || 'http://127.0.0.1:8080/index.html';
const MIN_PEAK = 0.01;
(async () => {
  const local = /127\.0\.0\.1|localhost/.test(URL);
  const b = await chromium.launch({
    proxy: (!local && process.env.HTTPS_PROXY) ? { server: process.env.HTTPS_PROXY } : undefined,
    args: ['--autoplay-policy=no-user-gesture-required', '--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-certificate-errors'],
  });
  const ctx = await b.newContext({ ...devices['Pixel 7'] });
  await ctx.addInitScript(() => {
    window.__peak = 0;
    const conn = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (target, ...rest) {
      if (target instanceof AudioDestinationNode) {
        const c = target.context;
        if (!c.__an) {
          c.__an = c.createAnalyser(); c.__an.fftSize = 2048; conn.call(c.__an, target);
          const buf = new Float32Array(2048);
          setInterval(() => { c.__an.getFloatTimeDomainData(buf); for (const v of buf) window.__peak = Math.max(window.__peak, Math.abs(v)); }, 50);
        }
        return conn.call(this, c.__an, ...rest);
      }
      return conn.call(this, target, ...rest);
    };
  });
  const p = await ctx.newPage();
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  await p.goto(URL, { timeout: 120000 });
  let peak = 0;
  for (let i = 0; i < 40 && peak < MIN_PEAK; i++) {
    await p.waitForTimeout(1000);
    peak = await p.evaluate(() => window.__peak);
  }
  await b.close();
  console.log(`web audio peak: ${peak.toFixed(4)} (need >= ${MIN_PEAK})` + (errors.length ? ` page errors: ${errors.join(' | ')}` : ''));
  if (peak < MIN_PEAK) { console.log('WEB AUDIO FAIL'); process.exit(1); }
  console.log('WEB AUDIO PASS');
})();
