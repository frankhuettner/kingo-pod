// CI: a script in a folder with a copy of Playwright of its own in node_modules, as a Vite project may hold one (the
// shell puts this file next to that copy). Every way to Playwright by its name must give kingo's copy, and a way to
// the other copy by its path must be refused with clickthrough's words (setup/claude/clickthrough-setup.js).
//   clickthrough clickthrough_copy.js
// Prints COPY <way> kingo | COPY <way> refused <words> | COPY <way> ANOTHER <file> | COPY <way> FAILED <words>, and
// COPY-DONE.
const fs = require('fs');
const path = require('path');
const kingo = fs.realpathSync(path.join(process.env.KINGO_PLAYWRIGHT, 'node_modules', 'playwright-core'));
const first = (e) => String(e && e.message).split('\n')[0].slice(0, 160);
const say = (way, what) => console.log('COPY ' + way + ' ' + what);
const ours = (file) => file.startsWith(kingo + path.sep);
const main = require('playwright-core');
const chromium = main.chromium;
say('require', ours(require.resolve('playwright-core')) ? 'kingo' : 'ANOTHER ' + require.resolve('playwright-core'));
function load(way, fn) {
  try {
    const m = fn();
    say(way, m && m.chromium === chromium && ours(require.resolve('playwright-core')) ? 'kingo' : 'ANOTHER');
  } catch (e) {
    say(way, (/^clickthrough[: ]/.test(first(e)) ? 'refused ' : 'FAILED ') + first(e));
  }
}
load('require-playwright', () => require('playwright'));
load('createRequire', () => require('module').createRequire(__filename)('playwright-core'));
load('require-path', () => require('./node_modules/playwright-core'));
load('require-file', () => require(path.join(__dirname, 'node_modules', 'playwright-core', 'index.js')));
(async () => {
  for (const [way, specifier] of [['import', 'playwright-core'], ['import-playwright', 'playwright'],
    ['import-path', './node_modules/playwright-core/index.mjs']]) {
    try {
      const m = await import(specifier);
      say(way, (m.chromium || (m.default && m.default.chromium)) === chromium && ours(require.resolve('playwright-core')) ? 'kingo' : 'ANOTHER');
    } catch (e) {
      say(way, (/^clickthrough[: ]/.test(first(e)) ? 'refused ' : 'FAILED ') + first(e));
    }
  }
  console.log('COPY-DONE');
})();
