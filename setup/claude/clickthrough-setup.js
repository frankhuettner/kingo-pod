// Loaded by `clickthrough` (bin/clickthrough) before the student's script, with node --require.
// chromium.launch() of playwright-core then starts the browser of look:
//   - without a window, and without Chrome's own sandbox: nono is the sandbox, as for look
//   - through nono's proxy, for pages on the internet. A program in the sandbox reaches the internet only through
//     that proxy. Under Linux Chrome finds it in HTTPS_PROXY by itself; on a Mac Chrome takes the system's settings
//     instead and gets net::ERR_ACCESS_DENIED (found on 14 Nov 2026). The proxy wants the user and password that
//     nono puts into HTTPS_PROXY; Playwright gives them to Chrome.
//   - as one program when KINGO_BROWSER_MODE=single, as look does
//   - with https pages and files only: no http://, and no WebSocket at all (below), except the one port of the
//     student's dev server with clickthrough --dev (KINGO_CLICKTHROUGH_DEV)
//
// Why no http. clickthrough is the one browser in the sandbox that runs the scripts of pages from the internet. Such a
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
//   2. in every context that clickthrough makes: http:// is aborted before it leaves, and clickthrough says why, once
//      per address; service workers are off; page.goto on an http address stops with the same plain words. The route of
//      lock 2 is always there, also without --dev, although a route turns off Chrome's HTTP cache: it is the second
//      lock, for a context in which the first should not hold.
// What still opens: https pages, files (file://), data:, blob: and about:.
//
// Whatever the script does (a review on 15 Nov 2026 found the ways around the locks below; each is closed now):
//   - a copy of Playwright of its own: a folder may hold one in node_modules (a Vite project), and Node.js takes that
//     copy before kingo's. require and import of playwright-core and playwright, and of their subpaths, always get
//     kingo's copy here (two hooks of Node.js, one for require and one for import); another copy, loaded by its path,
//     is refused with plain words.
//   - its own routes: Playwright asks the routes of a page before those of its context, and later routes before
//     earlier ones, so a route of the script came before lock 2. Now every route of the script asks lock 2 first, and
//     context.unrouteAll() leaves lock 2 in place. route.fetch() follows no redirect: Node.js would follow it outside
//     Chrome, past both locks; Chrome follows it through them.
//   - options: a context gets no proxy of its own (proxy is dropped, and clientCertificates is refused: for it
//     Playwright puts a proxy of its own in front of the context). The script's arguments for Chrome cannot change
//     where Chrome connects (--proxy-..., --host-rules, --host-resolver-rules and a debugging port are refused; on 15
//     Nov 2026 --host-rules sent the discard port to a service on the laptop), and ignoreDefaultArgs cannot drop
//     those of lock 1.
//   - another way to a browser: launchServer, connect, connectOverCDP, browser.bind and browser.newBrowserCDPSession
//     are refused (a client there could make a context with a proxy of its own), and so are firefox and webkit.
//     context.newCDPSession(page) stays: Chrome refuses Target.createBrowserContext and Target.attachToBrowserTarget
//     on the session of a page (tried on 15 Nov 2026).
// "Whatever the script does" means: whatever it does through Playwright's API. Not covered is a script that goes
// around it (Playwright's inner objects, whose names begin with _, or a Chrome or Node.js that it starts by itself).
// A request that the script sends itself (page.request, fetch of Node.js) is its own, as a curl of Claude is: no page
// chooses it.
//
// The dev server (clickthrough --dev <port>, Frank, 15 Nov 2026: "4. ja"). A dev server such as Vite's speaks http on
// localhost:<port> and reloads its page over a WebSocket on the same port. Lock 1 lets exactly this port go direct
// (the bypass list): http and WebSockets to localhost:<port>, 127.0.0.1:<port> and [::1]:<port>, and nothing else.
// The sandbox lets Claude connect to this one port too: kingo opens KINGO_DEV_PORT in the profile (5173 unless the
// student names another). Lock 2 lets an http request to the dev server through only when the page on top of the tab
// comes from the dev server itself, or when the script sends the tab there itself with page.goto: a page of the
// internet cannot fetch from the dev server, nor read anything of it, nor send the tab there (a form, location,
// window.open, a link, a redirect). Never a port of kingo-pod: bin/clickthrough refuses those.
// What stays open: a page of the internet could open a WebSocket to the dev server (lock 2 cannot see WebSockets);
// it reaches the student's dev server and nothing else, and Vite answers only its own page there.
'use strict';
const Module = require('module');
const fs = require('fs');
const path = require('path');
const { pathToFileURL, fileURLToPath } = require('url');

if (!process.env.KINGO_PLAYWRIGHT) throw new Error('clickthrough-setup.js is for clickthrough: run the script with  clickthrough <script.cjs>');
const PW_HOME = fs.realpathSync(process.env.KINGO_PLAYWRIGHT);   // bin/clickthrough names the folder of kingo's copy
const PW_CORE = path.join(PW_HOME, 'node_modules', 'playwright-core');

const MISSING_LIBRARY = 'the browser cannot start: a library of the system is missing. You cannot install it from inside ' +
  'the sandbox, so do not try. Ask the student to run this in their own terminal, in the kingo-pod folder, and to say ' +
  'yes to the question:  ./kingo claude browser';
const CLOSED = 'clickthrough opens https pages and files; http addresses and WebSockets are closed, so that no page can ' +
  'reach the services on this laptop (n8n, Langflow and the others). For a dev server on this laptop: clickthrough --dev <port>.';
const ONE_COPY = 'clickthrough gives every script kingo\'s playwright-core, whose browser keeps the pages away from the ' +
  'services on this laptop. Use  require(\'playwright-core\')  and  chromium.launch().';
const NOWHERE = '127.0.0.1:9';   // the discard port: nothing listens there, so what is sent there goes nowhere
const DEV = /^[1-9][0-9]{0,4}$/.test(process.env.KINGO_CLICKTHROUGH_DEV || '') ? process.env.KINGO_CLICKTHROUGH_DEV : '';
const DEV_HOSTS = ['localhost', '127.0.0.1', '[::1]'];
// Arguments for Chrome that would change where it connects, past lock 1. Chrome takes "-" for "--" too.
const NOT_THESE_ARGS = /^--?(proxy-|no-proxy-server|host-rules|host-resolver-rules|remote-debugging-|remote-allow-origins)/i;

// ── kingo's playwright-core, from a script in any folder ──────────────────────
const PLAYWRIGHT = /^(playwright-core|playwright)(\/.*)?$/;            // a name, as require and import take it
const A_COPY = /[\\/]node_modules[\\/](playwright|playwright-core)[\\/]/;  // a file of a copy, by its path
const ours = (file) => file === PW_CORE || file.startsWith(PW_CORE + path.sep);
const anotherCopy = (file) => new Error('clickthrough: the script loads a copy of Playwright of its own (' + file + '). ' + ONE_COPY);
const notInOurs = (name, e) => new Error('clickthrough: ' + name + ' is not in kingo\'s playwright-core (' +
  String(e && e.message).split('\n')[0] + '). ' + ONE_COPY);

const resolveFilename = Module._resolveFilename;   // require, require.resolve and createRequire
Module._resolveFilename = function (request, parent, isMain, options) {
  const name = typeof request === 'string' ? PLAYWRIGHT.exec(request) : null;
  if (name) {
    let file;
    try {
      file = resolveFilename.call(this, 'playwright-core' + (name[2] || ''), parent, isMain, { paths: [PW_HOME] });
    } catch (e) { throw notInOurs(request, e); }
    if (!ours(file)) throw anotherCopy(file);
    return file;
  }
  const file = resolveFilename.apply(this, arguments);
  if (typeof file === 'string' && A_COPY.test(file) && !ours(file)) throw anotherCopy(file);
  return file;
};
// import and import(): the hook of Node.js for modules. It does not see require (tried on 15 Nov 2026), so both.
if (typeof Module.registerHooks === 'function') {
  const from = pathToFileURL(path.join(PW_HOME, 'clickthrough.js')).href;   // as if imported from kingo's folder
  Module.registerHooks({
    resolve(specifier, context, next) {
      if ([...(context.conditions || [])].includes('require')) return next(specifier, context);   // the hook above
      const name = PLAYWRIGHT.exec(specifier);
      let found;
      try {
        found = name ? next('playwright-core' + (name[2] || ''), Object.assign({}, context, { parentURL: from }))
          : next(specifier, context);
      } catch (e) { if (name) throw notInOurs(specifier, e); throw e; }
      if (found && typeof found.url === 'string' && found.url.startsWith('file:')) {
        const file = fileURLToPath(found.url);
        if ((name || A_COPY.test(file)) && !ours(file)) throw anotherCopy(file);
      }
      return found;
    },
  });
}

const { chromium } = require(PW_CORE);

// ── lock 1: how Chrome starts ──────────────────────────────────────────────────
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

function noClientCertificates(o) {
  if (o.clientCertificates && o.clientCertificates.length) {
    throw new Error('clickthrough: clientCertificates is closed here. For them Playwright puts a proxy of its own in front ' +
      'of the browser, and that proxy would open http again. ' + CLOSED);
  }
  delete o.clientCertificates;
}

function withKingo(options, persistent) {
  const o = Object.assign({}, options);
  if (persistent) noClientCertificates(o);   // launchPersistentContext takes the options of a context too
  const theirs = (o.args || []).filter((a) => NOT_THESE_ARGS.test(String(a)));
  if (theirs.length) {
    throw new Error('clickthrough: ' + theirs.join(' ') + ' is closed here: clickthrough itself says where the browser ' +
      'connects. ' + CLOSED);
  }
  o.executablePath = process.env.KINGO_BROWSER;
  o.headless = true;              // chrome-headless-shell has no window to show
  o.chromiumSandbox = false;
  o.proxy = proxy();              // Playwright gives Chrome the proxy's user and password; none outside nono
  // Lock 1. These come after Playwright's own --proxy-server, and Chrome takes the last one.
  // https: nono's proxy, or straight out when there is none (outside nono). The SOCKS proxy is also the one for every
  // scheme without a rule of its own, so https needs one.
  const rules = 'https=' + (o.proxy ? o.proxy.server : 'direct://') + ';http=http://' + NOWHERE + ';socks=socks5://' + NOWHERE;
  const bypass = ['<-loopback>'].concat(DEV ? DEV_HOSTS.map((h) => h + ':' + DEV) : []).join(';');
  o.args = ['--no-sandbox', '--disable-gpu'].concat(o.args || [],
    ['--proxy-server=' + rules, '--proxy-bypass-list=' + bypass,
     '--force-webrtc-ip-handling-policy=disable_non_proxied_udp']);
  if (process.env.KINGO_BROWSER_MODE === 'single') o.args.push('--single-process');
  // ignoreDefaultArgs takes away arguments that Playwright passes, ours among them: not these
  if (Array.isArray(o.ignoreDefaultArgs)) o.ignoreDefaultArgs = o.ignoreDefaultArgs.filter((a) => !o.args.includes(a));
  if (persistent) o.serviceWorkers = 'block';
  return o;
}

function explain(e) {
  if (e && /error while loading shared libraries/.test(String(e.message))) e.message = MISSING_LIBRARY + '\n' + e.message;
  return e;
}

// ── lock 2: what a page asks for ───────────────────────────────────────────────
const closed = (url) => /^(http|ws):/i.test(String(url));
function isDev(url) {   // http or ws to the dev server's port on this laptop
  if (!DEV) return false;
  let u;
  try { u = new URL(String(url)); } catch (e) { return false; }
  return (u.protocol === 'http:' || u.protocol === 'ws:') && DEV_HOSTS.includes(u.hostname) && u.port === DEV;
}
const going = new WeakMap();   // a frame -> the address that page.goto of the script sends it to, while it goes there
const bases = new WeakMap();   // a context -> its baseURL, against which page.goto takes an address such as '/'
const bare = (url) => String(url).split('#')[0];
// The request may go to the dev server: the page on top of the tab comes from it, or the script sends the tab there
// itself with page.goto (the request, or the first of its redirects, is the one that page.goto asked for). Not when
// a page sends the tab there: a form, location, window.open, a link.
function fromDev(request) {
  try {
    const frame = request.frame();
    const top = frame.page().mainFrame();
    if (isDev(top.url())) return true;
    if (frame !== top || !request.isNavigationRequest()) return false;
    let first = request;
    while (first.redirectedFrom()) first = first.redirectedFrom();
    return going.has(top) && first.method() === 'GET' && bare(first.url()) === bare(going.get(top));
  } catch (e) {
    return false;   // a request without a frame (a service worker's, a popup's first): not to the dev server
  }
}
const told = new Set();
function tell(url, why) {
  let where = String(url);
  try { where = new URL(where).origin; } catch (e) { /* keep it as it is */ }
  if (told.has(where + why)) return;
  told.add(where + why);
  process.stderr.write('clickthrough: closed ' + where + ' (' + why + '). ' + CLOSED + '\n');
}

const done = new WeakSet();   // the prototypes that are wrapped already
// route.fetch() sends the request from Node.js, outside Chrome: no redirect there, and no http address of its own
function guardFetch(proto) {
  if (done.has(proto)) return;
  done.add(proto);
  const fetch = proto.fetch;
  proto.fetch = function (options) {
    const o = Object.assign({}, options);
    if (o.url !== undefined && closed(o.url) && !isDev(o.url)) return Promise.reject(new Error(CLOSED + ' Not fetched: ' + o.url));
    o.maxRedirects = 0;   // the answer goes to Chrome as it is, and Chrome follows a redirect through both locks
    return fetch.call(this, o);
  };
}
// Lock 2's question for one request. It aborts what is closed and returns that promise, or null when the request
// may go on.
function stop(route) {
  guardFetch(Object.getPrototypeOf(route));
  const request = route.request();
  const url = request.url();
  if (!closed(url) || (isDev(url) && fromDev(request))) return null;
  tell(url, isDev(url) ? 'a page that does not come from the dev server asked for it' : 'a page asked for it');
  return route.abort('blockedbyclient').catch(() => {});
}
// Every route of the script asks lock 2 first, in whatever order Playwright asks the routes.
const guards = new WeakMap();   // a handler of the script -> the same handler behind lock 2
function guarded(handler) {
  if (typeof handler !== 'function') return handler;
  if (!guards.has(handler)) guards.set(handler, function (route) { return stop(route) || handler.apply(this, arguments); });
  return guards.get(handler);
}
let contextRoute = null;   // BrowserContext.route as Playwright has it, for lock 2's own route
function guardRoutes(proto, context) {
  if (done.has(proto)) return;
  done.add(proto);
  const route = proto.route;
  const unroute = proto.unroute;
  proto.route = function (url, handler, options) { return route.call(this, url, guarded(handler), options); };
  proto.unroute = function (url, handler) { return unroute.call(this, url, guards.has(handler) ? guards.get(handler) : handler); };
  if (!context) return;
  contextRoute = route;
  const unrouteAll = proto.unrouteAll;
  proto.unrouteAll = async function (options) {   // all routes of the script go, lock 2 stays
    await unrouteAll.call(this, options);
    if (locked.has(this)) await lockRoute(this);
  };
}
const lockRoute = (context) => contextRoute.call(context, (url) => closed(url.href), (route) => stop(route) || route.fallback());

// page.goto and frame.goto on an http address: the plain words instead of net::ERR_BLOCKED_BY_CLIENT
function guardGoto(frame) {
  const proto = Object.getPrototypeOf(frame);
  if (done.has(proto)) return;
  done.add(proto);
  const goto = proto.goto;
  proto.goto = async function (url, options) {
    let target = String(url);
    try { target = new URL(target, bases.get(this.page().context())).href; } catch (e) { /* keep it as it is */ }
    if (closed(target) && !isDev(target)) throw new Error(CLOSED + ' Not opened: ' + url);
    going.set(this, target);
    try { return await goto.call(this, url, options); } catch (e) {
      if (e && /ERR_PROXY_CONNECTION_FAILED/.test(String(e.message))) {
        e.message += '\nIf this page sends the browser on to an http address, that is why: ' + CLOSED;
      }
      throw e;
    } finally {
      if (going.get(this) === target) going.delete(this);
    }
  };
}

// Lock 2, for one context: before it gets its first page
const locked = new WeakSet();
async function lock(context, options) {
  if (locked.has(context)) return context;
  locked.add(context);
  bases.set(context, options && options.baseURL);
  guardRoutes(Object.getPrototypeOf(context), true);
  await lockRoute(context);
  const watch = (page) => {
    guardRoutes(Object.getPrototypeOf(page), false);
    guardGoto(page.mainFrame());
    page.on('websocket', (ws) => { if (!isDev(ws.url())) tell(ws.url(), 'a page asked for a WebSocket'); });
  };
  context.pages().forEach(watch);
  context.on('page', watch);
  return context;
}

// ── the ways to a browser ──────────────────────────────────────────────────────
const closedWay = (what) => async function () {
  throw new Error('clickthrough: ' + what + ' is closed here: a client there could make a context with a proxy of its ' +
    'own, past the locks of clickthrough. Start the browser with  chromium.launch()  and use its pages.');
};
function onlyChromium(type) {
  if (type.name() !== 'chromium') {
    throw new Error('clickthrough has one browser, Chrome: use chromium, not ' + type.name() + '.');
  }
}
function lockBrowser(browser) {
  const proto = Object.getPrototypeOf(browser);
  if (done.has(proto)) return browser;
  done.add(proto);
  const newContext = proto.newContext;   // browser.newPage() makes its context with this one too
  proto.newContext = async function (options) {
    const o = Object.assign({}, options, { serviceWorkers: 'block' });
    noClientCertificates(o);
    delete o.proxy;                      // a context of its own with another proxy would open http again
    return lock(await newContext.call(this, o), o);
  };
  proto.newBrowserCDPSession = closedWay('browser.newBrowserCDPSession()');
  proto.bind = closedWay('browser.bind()');
  return browser;
}

// On the prototype: chromium, firefox and webkit share it, and so does every other playwright-core object of the script.
const types = Object.getPrototypeOf(chromium);
const launch = types.launch;
const launchPersistentContext = types.launchPersistentContext;
types.launch = async function (options) {
  onlyChromium(this);
  try { return lockBrowser(await launch.call(this, withKingo(options))); } catch (e) { throw explain(e); }
};
types.launchPersistentContext = async function (dir, options) {
  onlyChromium(this);
  let context;
  try { context = await launchPersistentContext.call(this, dir, withKingo(options, true)); } catch (e) { throw explain(e); }
  if (context.browser()) lockBrowser(context.browser());
  return lock(context, options);
};
types.launchServer = closedWay('chromium.launchServer()');
types.connect = closedWay('chromium.connect()');
types.connectOverCDP = closedWay('chromium.connectOverCDP()');
