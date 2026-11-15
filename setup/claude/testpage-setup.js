// Loaded by `testpage` (bin/testpage) before the student's script, with node --require.
// chromium.launch() of playwright-core then starts the browser of look:
//   - without a window, and without Chrome's own sandbox: nono is the sandbox, as for look
//   - through nono's proxy, for pages on the internet. A program in the sandbox reaches the internet only through
//     that proxy. Under Linux Chrome finds it in HTTPS_PROXY by itself; on a Mac Chrome takes the system's settings
//     instead and gets net::ERR_ACCESS_DENIED (found on 14 Nov 2026). The proxy wants the user and password that
//     nono puts into HTTPS_PROXY; Playwright gives them to Chrome.
//   - as one program when KINGO_BROWSER_MODE=single, as look does
//   - with https pages and files only: no http://, and no WebSocket at all (below), except the one port of the
//     student's dev server with testpage --dev (KINGO_TESTPAGE_DEV)
//
// Why no http. testpage is the one browser in the sandbox that runs the scripts of pages from the internet. Such a
// script could send requests to the services of this laptop: when the network is open, nono's proxy lets every
// address through, the laptop's own too (127.0.0.1, or a name such as 127.0.0.1.nip.io that points to it), and under
// WSL2 nothing stops a direct connection to 127.0.0.1. n8n's webhooks and Langflow answer a page of any origin (found
// on 15 Nov 2026). The services of kingo-pod speak http, never https, so closing http and WebSockets closes the way
// to them. Two locks:
//   1. in Chrome itself: https goes to nono's proxy; http goes to a proxy that is not there (the discard port), the
//      laptop's own addresses too (<-loopback>: none goes direct). WebSockets, ws:// and wss://, go to a SOCKS proxy
//      that is not there either: Chrome sends a WebSocket to the SOCKS proxy first, else to the one for https
//      (RFC 6455, 4.1.3; on 15 Nov 2026 a ws:// went to the laptop through the https proxy), and has no rule for ws
//      alone. This holds for every request of every page, frame, worker and redirect, whatever the script does.
//   2. in every context that testpage makes: http:// is aborted before it leaves, and testpage says why, once per
//      address; service workers are off; page.goto on an http address stops with the same plain words.
// What still opens: https pages, files (file://), data:, blob: and about:.
//
// The dev server (testpage --dev <port>, Frank, 15 Nov 2026: "4. ja"). A dev server such as Vite's speaks http on
// localhost:<port> and reloads its page over a WebSocket on the same port. Lock 1 lets exactly this port go direct
// (the bypass list): http and WebSockets to localhost:<port>, 127.0.0.1:<port> and [::1]:<port>, and nothing else.
// The sandbox lets Claude connect to this one port too: kingo opens KINGO_DEV_PORT in the profile (5173 unless the
// student names another). Lock 2 lets an http request to the dev server through only when the page on top of the tab
// comes from the dev server itself, or when the tab itself goes there (page.goto, a link): a page of the internet
// cannot fetch from the dev server, nor read anything of it. Never a port of kingo-pod: bin/testpage refuses those.
// What stays open: a page of the internet could open a WebSocket to the dev server (lock 2 cannot see WebSockets);
// it reaches the student's dev server and nothing else, and Vite answers only its own page there.
'use strict';
const { chromium } = require('playwright-core');

const MISSING_LIBRARY = 'the browser cannot start: a library of the system is missing. You cannot install it from inside ' +
  'the sandbox, so do not try. Ask the student to run this in their own terminal, in the kingo-pod folder, and to say ' +
  'yes to the question:  ./kingo claude browser';
const CLOSED = 'testpage opens https pages and files; http addresses and WebSockets are closed, so that no page can ' +
  'reach the services on this laptop (n8n, Langflow and the others). For a dev server on this laptop: testpage --dev <port>.';
const NOWHERE = '127.0.0.1:9';   // the discard port: nothing listens there, so what is sent there goes nowhere
const DEV = /^\d+$/.test(process.env.KINGO_TESTPAGE_DEV || '') ? process.env.KINGO_TESTPAGE_DEV : '';
const DEV_HOSTS = ['localhost', '127.0.0.1', '[::1]'];

function proxy() {
  const raw = process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy;
  if (!raw) return undefined;
  let url;
  try { url = new URL(raw); } catch (e) { return undefined; }
  const p = { server: url.protocol + '//' + url.host };
  if (url.username) p.username = decodeURIComponent(url.username);
  if (url.password) p.password = decodeURIComponent(url.password);
  return p;
}

function withKingo(options, persistent) {
  const o = Object.assign({}, options);
  o.executablePath = process.env.KINGO_BROWSER;
  o.headless = true;              // chrome-headless-shell has no window to show
  o.chromiumSandbox = false;
  const p = proxy();
  if (p) o.proxy = p; else delete o.proxy;   // Playwright gives Chrome the proxy's user and password
  // Lock 1. These come after Playwright's own --proxy-server, and Chrome takes the last one.
  // https: nono's proxy, or straight out when there is none (outside nono). The SOCKS proxy is also the one for every
  // scheme without a rule of its own, so https needs one.
  const rules = 'https=' + (p ? p.server : 'direct://') + ';http=http://' + NOWHERE + ';socks=socks5://' + NOWHERE;
  const bypass = ['<-loopback>'].concat(DEV ? DEV_HOSTS.map((h) => h + ':' + DEV) : []).join(';');
  o.args = ['--no-sandbox', '--disable-gpu'].concat(o.args || [],
    ['--proxy-server=' + rules, '--proxy-bypass-list=' + bypass,
     '--force-webrtc-ip-handling-policy=disable_non_proxied_udp']);
  if (process.env.KINGO_BROWSER_MODE === 'single') o.args.push('--single-process');
  if (persistent) o.serviceWorkers = 'block';   // launchPersistentContext takes the options of a context too
  return o;
}

function explain(e) {
  if (e && /error while loading shared libraries/.test(String(e.message))) e.message = MISSING_LIBRARY + '\n' + e.message;
  return e;
}

const closed = (url) => /^(http|ws):/i.test(String(url));
function isDev(url) {   // http or ws to the dev server's port on this laptop
  if (!DEV) return false;
  let u;
  try { u = new URL(String(url)); } catch (e) { return false; }
  return (u.protocol === 'http:' || u.protocol === 'ws:') && DEV_HOSTS.includes(u.hostname) && u.port === DEV;
}
// The request may go to the dev server: the tab goes there itself, or the page on top of the tab comes from it.
function fromDev(request) {
  try {
    const frame = request.frame();
    const top = frame.page().mainFrame();
    if (request.isNavigationRequest() && frame === top) return true;
    return isDev(top.url());
  } catch (e) {
    return false;   // a request without a frame (a service worker's): not to the dev server
  }
}
const told = new Set();
function tell(url, why) {
  let where = String(url);
  try { where = new URL(where).origin; } catch (e) { /* keep it as it is */ }
  if (told.has(where + why)) return;
  told.add(where + why);
  process.stderr.write('testpage: closed ' + where + ' (' + why + '). ' + CLOSED + '\n');
}

// page.goto and frame.goto on an http address: the plain words instead of net::ERR_BLOCKED_BY_CLIENT
function guardGoto(frame) {
  const proto = Object.getPrototypeOf(frame);
  if (proto.__kingoGoto) return;
  const original = proto.goto;
  proto.goto = async function (url, options) {
    if (closed(url) && !isDev(url)) throw new Error(CLOSED + ' Not opened: ' + url);
    try { return await original.call(this, url, options); } catch (e) {
      if (e && /ERR_PROXY_CONNECTION_FAILED/.test(String(e.message))) {
        e.message += '\nIf this page sends the browser on to an http address, that is why: ' + CLOSED;
      }
      throw e;
    }
  };
  proto.__kingoGoto = true;
}

// Lock 2, for one context: before it gets its first page
async function lock(context) {
  if (context.__kingoLocked) return context;
  context.__kingoLocked = true;
  await context.route((url) => closed(url.href), (route) => {
    const request = route.request();
    if (isDev(request.url()) && fromDev(request)) return route.fallback();
    tell(request.url(), isDev(request.url()) ? 'a page that does not come from the dev server asked for it'
      : 'a page asked for it');
    return route.abort('blockedbyclient');
  });
  const watch = (page) => {
    guardGoto(page.mainFrame());
    page.on('websocket', (ws) => { if (!isDev(ws.url())) tell(ws.url(), 'a page asked for a WebSocket'); });
  };
  context.pages().forEach(watch);
  context.on('page', watch);
  return context;
}

function lockBrowser(browser) {
  const newContext = browser.newContext.bind(browser);   // browser.newPage() makes its context with this one too
  browser.newContext = async (options) => {
    const o = Object.assign({}, options, { serviceWorkers: 'block' });
    delete o.proxy;                                       // a context of its own with another proxy would open http again
    return lock(await newContext(o));
  };
  return browser;
}

const launch = chromium.launch.bind(chromium);
const launchPersistentContext = chromium.launchPersistentContext.bind(chromium);
chromium.launch = async (options) => {
  try { return lockBrowser(await launch(withKingo(options))); } catch (e) { throw explain(e); }
};
chromium.launchPersistentContext = async (dir, options) => {
  try { return await lock(await launchPersistentContext(dir, withKingo(options, true))); } catch (e) { throw explain(e); }
};
