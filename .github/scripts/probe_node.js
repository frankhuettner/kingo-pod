// CI: under the lock of setup/claude/no_unix_sockets.py, Node.js must still start programs (it gives them their
// pipes with socketpairs) and must not reach a Unix socket.   node probe_node.js /var/run/docker.sock
const cp = require('child_process');
const net = require('net');
const path = process.argv[2];
const sync = cp.execFileSync('sh', ['-c', 'echo sync | cat']).toString().trim();
cp.exec('echo async | cat', (error, stdout) => {
  if (error || sync !== 'sync' || stdout.trim() !== 'async') {
    console.log('node: a child did not run');
    process.exit(2);
  }
  const socket = net.connect(path);
  socket.on('connect', () => { console.log('node: children run; CONNECTED'); process.exit(0); });
  socket.on('error', (e) => { console.log('node: children run; refused with ' + e.code); process.exit(0); });
});
