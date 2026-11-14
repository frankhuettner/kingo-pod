// Drives Playwright's MCP server over stdin and stdout, as Claude Code does: a form is filled in and sent.
//   node mcp_drive.js <address of the page> -- <command of the server> [arguments ...]
// Prints one line per step, and at the end "MCP-RESULT ok" or "MCP-RESULT failed: ...".
const { spawn } = require('child_process');
const cut = process.argv.indexOf('--');
const url = process.argv[2], cmd = process.argv.slice(cut + 1);
const child = spawn(cmd[0], cmd.slice(1), { stdio: ['pipe', 'pipe', 'pipe'] });
let buf = '', id = 0, errText = '';
const waiting = new Map();
child.stderr.on('data', d => { errText += d; });
child.stdout.on('data', d => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!line) continue;
    let msg; try { msg = JSON.parse(line); } catch (e) { continue; }
    if (msg.id !== undefined && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
  }
});
function call(method, params) {
  return new Promise((resolve, reject) => {
    const my = ++id;
    const timer = setTimeout(() => reject(new Error(method + ': no answer in 60 seconds')), 60000);
    waiting.set(my, msg => { clearTimeout(timer); msg.error ? reject(new Error(method + ': ' + JSON.stringify(msg.error))) : resolve(msg.result); });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: my, method, params }) + '\n');
  });
}
const text = r => (r.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
async function tool(name, args) {
  const r = await call('tools/call', { name, arguments: args });
  const t = text(r);
  if (r.isError) throw new Error(name + ': ' + t.slice(0, 600));
  console.log('   step  ' + name + ' ' + JSON.stringify(args).slice(0, 80) + ': ' + t.length + ' characters back');
  return t;
}
function done(line, code) { console.log(line); try { child.kill(); } catch (e) {} setTimeout(() => process.exit(code), 300); }
child.on('exit', (code, sig) => { if (!finished) done('MCP-RESULT failed: the server ended (code ' + code + ', signal ' + sig + '): ' + errText.slice(-600).replace(/\n/g, ' | '), 1); });
let finished = false;
(async () => {
  const init = await call('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'kingo-trial', version: '0' } });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  console.log('   step  initialize: ' + init.serverInfo.name + ' ' + init.serverInfo.version);
  const tools = (await call('tools/list', {})).tools;
  console.log('   step  tools/list: ' + tools.length + ' tools, their descriptions and schemas are ' + JSON.stringify(tools).length + ' characters');
  if (process.env.MCP_SHOW_TOOLS) for (const t of tools) console.log('         ' + t.name + ' ' + JSON.stringify(t.inputSchema.properties ? Object.keys(t.inputSchema.properties) : []));
  let snap = await tool('browser_navigate', { url });
  if (process.env.MCP_ONLY_NAVIGATE) {   // only: does the page arrive? MCP_ONLY_NAVIGATE holds a text of the page
    if (!snap.includes(process.env.MCP_ONLY_NAVIGATE)) snap = await tool('browser_snapshot', {});
    finished = true;
    return snap.includes(process.env.MCP_ONLY_NAVIGATE) ? done('MCP-RESULT ok: the page arrived ("' + process.env.MCP_ONLY_NAVIGATE + '" is in the snapshot)', 0)
      : done('MCP-RESULT failed: the page did not arrive: ' + snap.slice(0, 500).replace(/\n/g, ' | '), 1);
  }
  if (!/textbox "Name"/.test(snap)) snap = await tool('browser_snapshot', {});
  const ref = (label) => { const m = snap.match(new RegExp(label + '[^\\n]*\\[ref=([a-z0-9]+)\\]')); if (!m) throw new Error('no ' + label + ' in the snapshot: ' + snap.slice(0, 400)); return m[1]; };
  const T = process.env.MCP_TARGET_KEY || 'target';
  await tool('browser_type', { element: 'Name', [T]: ref('textbox "Name"'), text: 'Mina' });
  await tool('browser_select_option', { element: 'Product', [T]: ref('combobox "Product"'), values: ['Coffee'] });
  let after = await tool('browser_click', { element: 'Order', [T]: ref('button "Order"') });
  if (!/Thank you/.test(after)) after = await tool('browser_snapshot', {});
  finished = true;
  if (/Thank you, Mina: 1 Coffee/.test(after)) done('MCP-RESULT ok: the page answered "Thank you, Mina: 1 Coffee"', 0);
  else done('MCP-RESULT failed: the answer of the page is not in the snapshot: ' + after.slice(0, 400).replace(/\n/g, ' | '), 1);
})().catch(e => { finished = true; done('MCP-RESULT failed: ' + String(e.message).slice(0, 900).replace(/\n/g, ' | ') + (errText ? ' || stderr: ' + errText.slice(-300).replace(/\n/g, ' | ') : ''), 1); });
