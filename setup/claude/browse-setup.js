// Loaded by `browse` (bin/browse) before the student's script, with node --require.
// chromium.launch() of playwright-core then starts the browser of look:
//   - without a window, and without Chrome's own sandbox: nono is the sandbox, as for look
//   - through nono's proxy, for pages on the internet. A program in the sandbox reaches the internet only through
//     that proxy. Under Linux Chrome finds it in HTTPS_PROXY by itself; on a Mac Chrome takes the system's settings
//     instead and gets net::ERR_ACCESS_DENIED (found on 14 Nov 2026). The proxy wants the user and password that
//     nono puts into HTTPS_PROXY; Playwright gives them to Chrome.
//   - as one program when KINGO_BROWSER_MODE=single, as look does
'use strict';
const { chromium } = require('playwright-core');

const MISSING_LIBRARY = 'the browser cannot start: a library of the system is missing. You cannot install it from inside ' +
  'the sandbox, so do not try. Ask the student to run this in their own terminal, in the kingo-pod folder, and to say ' +
  'yes to the question:  ./kingo claude browser';

function proxy() {
  const raw = process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy;
  if (!raw) return undefined;
  let url;
  try { url = new URL(raw); } catch (e) { return undefined; }
  // this laptop itself not through the proxy (Playwright would send it there otherwise)
  const p = { server: url.protocol + '//' + url.host, bypass: 'localhost,127.0.0.1,[::1]' };
  if (url.username) p.username = decodeURIComponent(url.username);
  if (url.password) p.password = decodeURIComponent(url.password);
  return p;
}

function withKingo(options) {
  const o = Object.assign({}, options);
  o.executablePath = process.env.KINGO_BROWSER;
  o.headless = true;              // chrome-headless-shell has no window to show
  o.chromiumSandbox = false;
  o.args = ['--no-sandbox', '--disable-gpu'].concat(o.args || []);
  if (process.env.KINGO_BROWSER_MODE === 'single') o.args.push('--single-process');
  if (!o.proxy) { const p = proxy(); if (p) o.proxy = p; }
  return o;
}

function explain(e) {
  if (e && /error while loading shared libraries/.test(String(e.message))) e.message = MISSING_LIBRARY + '\n' + e.message;
  return e;
}

for (const name of ['launch', 'launchPersistentContext']) {
  const original = chromium[name].bind(chromium);
  chromium[name] = name === 'launch'
    ? async (options) => { try { return await original(withKingo(options)); } catch (e) { throw explain(e); } }
    : async (dir, options) => { try { return await original(dir, withKingo(options)); } catch (e) { throw explain(e); } };
}
