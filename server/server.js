
const net = require('net');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 7777;
const BROADCAST_HZ = 15;
const STALE_MS = 8000; // drop a player's last-known state if nothing arrives for this long

const MAX_CONNECTIONS = 500;
const MAX_CONNECTIONS_PER_IP = 20;
const MAX_BUFFER_BYTES = 8 * 1024;
const MAX_MSGS_PER_SEC = 120; // real gameplay sends every 2 frames; this is generous headroom
const IDLE_TIMEOUT_MS = 30 * 1000;
const MAX_LOBBIES = 500;
const MAX_LOBBY_MEMBERS = 16;

let nextId = 1;
let nextLobbyId = 1;
const clients = new Map();  // id -> { socket, buffer, name, lobbyId, ip, msgCount, msgWindowStart }
const states = new Map();   // id -> { x, y, facingRight, animHash, animTime, lastUpdate }
const lobbies = new Map();  // lobbyId -> { name, hostId, members: Set<id> }
const ipCounts = new Map(); // ip -> count of open connections

function send(socket, obj) {
  try { socket.write(JSON.stringify(obj) + '\n'); } catch (e) { /* socket already gone */ }
}

function lobbySummary(lobbyId) {
  const l = lobbies.get(lobbyId);
  if (!l) return null;
  const hostClient = clients.get(l.hostId);
  return { id: lobbyId, name: l.name, hostName: hostClient ? hostClient.name : '?', count: l.members.size };
}

function leaveLobby(id) {
  const c = clients.get(id);
  if (!c || c.lobbyId == null) return;
  const l = lobbies.get(c.lobbyId);
  if (l) {
    l.members.delete(id);
    if (l.members.size === 0) lobbies.delete(c.lobbyId);
  }
  c.lobbyId = null;
}

function removeClient(id) {
  const c = clients.get(id);
  if (c) {
    const n = (ipCounts.get(c.ip) || 1) - 1;
    if (n <= 0) ipCounts.delete(c.ip); else ipCounts.set(c.ip, n);
  }
  leaveLobby(id);
  clients.delete(id);
  states.delete(id);
  console.log(`[-] player ${id} disconnected (${clients.size} connected)`);
}

const server = net.createServer((socket) => {
  const ip = socket.remoteAddress || 'unknown';

  if (clients.size >= MAX_CONNECTIONS) {
    socket.destroy();
    return;
  }
  const ipCount = ipCounts.get(ip) || 0;
  if (ipCount >= MAX_CONNECTIONS_PER_IP) {
    socket.destroy();
    return;
  }
  ipCounts.set(ip, ipCount + 1);

  const id = nextId++;
  socket.setNoDelay(true);
  socket.setTimeout(IDLE_TIMEOUT_MS, () => socket.destroy());
  clients.set(id, {
    socket, buffer: '', name: 'Player' + id, nameColor: '#FFFFFF', dotColor: '#3399FF',
    lobbyId: null, ip, msgCount: 0, msgWindowStart: Date.now(),
  });
  send(socket, { type: 'welcome', id });
  console.log(`[+] player ${id} connected from ${ip} (${clients.size} connected)`);

  socket.on('data', (chunk) => {
    const c = clients.get(id);
    if (!c) return;

    if (c.buffer.length + chunk.length > MAX_BUFFER_BYTES) {
      socket.destroy();
      return;
    }
    c.buffer += chunk.toString('utf8');

    let idx;
    while ((idx = c.buffer.indexOf('\n')) >= 0) {
      const line = c.buffer.slice(0, idx);
      c.buffer = c.buffer.slice(idx + 1);
      if (!line) continue;

      const now = Date.now();
      if (now - c.msgWindowStart >= 1000) {
        c.msgWindowStart = now;
        c.msgCount = 0;
      }
      c.msgCount++;
      if (c.msgCount > MAX_MSGS_PER_SEC) {
        socket.destroy();
        return;
      }

      let msg;
      try { msg = JSON.parse(line); } catch (e) { continue; }
      if (!msg || typeof msg !== 'object') continue;

      try { handleMessage(id, msg); } catch (e) { console.error(`[!] handleMessage error (player ${id}):`, e); }
    }
  });

  const cleanup = () => removeClient(id);
  socket.on('close', cleanup);
  socket.on('error', cleanup);
});

function clampNum(v, fallback, min, max) {
  if (!Number.isFinite(v)) return fallback;
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

function handleMessage(id, msg) {
  const c = clients.get(id);
  if (!c) return;

  switch (msg.type) {
    case 'state': {
      if (typeof msg.name === 'string' && msg.name.length > 0) c.name = msg.name.slice(0, 24);
      // per-client, not per-frame, so a snapshot still includes it even without a fresh state line this tick
      const hexRe = /^#[0-9a-fA-F]{6}$/;
      if (hexRe.test(msg.nameColor)) c.nameColor = msg.nameColor;
      if (hexRe.test(msg.dotColor)) c.dotColor = msg.dotColor;
      states.set(id, {
        x: clampNum(msg.x, 0, -1e6, 1e6),
        y: clampNum(msg.y, 0, -1e6, 1e6),
        facingRight: !!msg.facingRight,
        animHash: Number.isFinite(msg.animHash) ? (msg.animHash | 0) : 0,
        animTime: clampNum(msg.animTime, 0, -1e6, 1e6),
        lastUpdate: Date.now(),
      });
      break;
    }
    case 'host': {
      if (lobbies.size >= MAX_LOBBIES) {
        send(c.socket, { type: 'join_failed', reason: 'Server is full' });
        break;
      }
      // applied before any c.name read, including the default lobby-name fallback
      if (typeof msg.playerName === 'string' && msg.playerName.trim().length > 0) c.name = msg.playerName.slice(0, 24);
      leaveLobby(id);
      const lobbyId = nextLobbyId++;
      const name = (typeof msg.name === 'string' && msg.name.trim().length > 0) ? msg.name.slice(0, 32) : (c.name + "'s lobby");
      lobbies.set(lobbyId, { name, hostId: id, members: new Set([id]) });
      c.lobbyId = lobbyId;
      send(c.socket, { type: 'hosted', lobbyId, name });
      console.log(`[lobby] ${id} hosted "${name}" (#${lobbyId})`);
      break;
    }
    case 'list_lobbies': {
      const list = [...lobbies.keys()].map(lobbySummary).filter(Boolean);
      send(c.socket, { type: 'lobby_list', lobbies: list });
      break;
    }
    case 'join_lobby': {
      if (typeof msg.playerName === 'string' && msg.playerName.trim().length > 0) c.name = msg.playerName.slice(0, 24);
      const lobbyId = msg.lobbyId | 0;
      const l = lobbies.get(lobbyId);
      if (!l) {
        send(c.socket, { type: 'join_failed', reason: 'Lobby not found' });
        break;
      }
      if (l.members.size >= MAX_LOBBY_MEMBERS) {
        send(c.socket, { type: 'join_failed', reason: 'Lobby is full' });
        break;
      }
      leaveLobby(id);
      l.members.add(id);
      c.lobbyId = lobbyId;
      send(c.socket, { type: 'joined', lobbyId, name: l.name });
      console.log(`[lobby] ${id} joined "${l.name}" (#${lobbyId})`);
      break;
    }
    case 'leave_lobby': {
      leaveLobby(id);
      send(c.socket, { type: 'left' });
      break;
    }
    case 'chat': {
      if (c.lobbyId == null) break;
      const l = lobbies.get(c.lobbyId);
      if (!l) break;
      const text = typeof msg.text === 'string' ? msg.text.slice(0, 240).trim() : '';
      if (!text) break;
      for (const memberId of l.members) {
        const mc = clients.get(memberId);
        if (mc) send(mc.socket, { type: 'chat', from: c.name, fromColor: c.nameColor, text });
      }
      console.log(`[chat] #${c.lobbyId} ${c.name}: ${text}`);
      break;
    }
  }
}

setInterval(() => {
  const now = Date.now();
  for (const [id, s] of states) {
    if (now - s.lastUpdate > STALE_MS) states.delete(id);
  }

  for (const l of lobbies.values()) {
    const members = [...l.members];
    const all = members
      .filter((id) => states.has(id))
      .map((id) => ({
        id,
        name: clients.get(id).name,
        nameColor: clients.get(id).nameColor,
        dotColor: clients.get(id).dotColor,
        ...states.get(id),
      }));

    for (const id of members) {
      const c = clients.get(id);
      if (!c) continue;
      send(c.socket, {
        type: 'snapshot',
        players: all.filter((p) => p.id !== id).map(({ lastUpdate, ...rest }) => rest),
      });
    }
  }
}, 1000 / BROADCAST_HZ);

process.on('uncaughtException', (e) => console.error('[!] uncaught exception:', e));
process.on('unhandledRejection', (e) => console.error('[!] unhandled rejection:', e));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`[i] ${sig} received, shutting down`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}

server.listen(PORT, () => {
  console.log(`IGTAP multiplayer relay listening on :${PORT}`);
});
