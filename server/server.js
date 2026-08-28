
const WebSocket = require('ws');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 7777;
const BROADCAST_HZ = 15;
const STALE_MS = 8000; // drop a player's last-known state if nothing arrives for this long

const MAX_CONNECTIONS = 500;
const MAX_CONNECTIONS_PER_IP = 20;
const MAX_PAYLOAD_BYTES = 8 * 1024;
const MAX_MSGS_PER_SEC = 120; // real gameplay sends every 2 frames; this is generous headroom
const HEARTBEAT_MS = 15 * 1000;
const MAX_LOBBIES = 500;
const MAX_LOBBY_MEMBERS = 16;

let nextId = 1;
let nextLobbyId = 1;
const clients = new Map();  // id -> { ws, name, lobbyId, ip, msgCount, msgWindowStart }
const states = new Map();   // id -> { x, y, facingRight, animHash, animTime, lastUpdate }
const lobbies = new Map();  // lobbyId -> { name, hostId, members: Set<id> }
const ipCounts = new Map(); // ip -> count of open connections

function send(ws, obj) {
  if (ws.readyState !== WebSocket.OPEN) return;
  try { ws.send(JSON.stringify(obj)); } catch (e) { /* socket already gone */ }
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

const wss = new WebSocket.Server({
  port: PORT,
  maxPayload: MAX_PAYLOAD_BYTES,
  verifyClient: (info, cb) => {
    const ip = info.req.socket.remoteAddress || 'unknown';
    if (clients.size >= MAX_CONNECTIONS) { cb(false, 503, 'Server full'); return; }
    if ((ipCounts.get(ip) || 0) >= MAX_CONNECTIONS_PER_IP) { cb(false, 429, 'Too many connections from this address'); return; }
    cb(true);
  },
});

wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress || 'unknown';
  ipCounts.set(ip, (ipCounts.get(ip) || 0) + 1);

  const id = nextId++;
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  clients.set(id, {
    ws, name: 'Player' + id, nameColor: '#FFFFFF', dotColor: '#3399FF',
    lobbyId: null, ip, msgCount: 0, msgWindowStart: Date.now(),
  });
  send(ws, { type: 'welcome', id });
  console.log(`[+] player ${id} connected from ${ip} (${clients.size} connected)`);

  ws.on('message', (data) => {
    const c = clients.get(id);
    if (!c) return;

    const now = Date.now();
    if (now - c.msgWindowStart >= 1000) {
      c.msgWindowStart = now;
      c.msgCount = 0;
    }
    c.msgCount++;
    if (c.msgCount > MAX_MSGS_PER_SEC) {
      ws.close(1008, 'rate limit');
      return;
    }

    let msg;
    try { msg = JSON.parse(data.toString('utf8')); } catch (e) { return; }
    if (!msg || typeof msg !== 'object') return;

    try { handleMessage(id, msg); } catch (e) { console.error(`[!] handleMessage error (player ${id}):`, e); }
  });

  const cleanup = () => removeClient(id);
  ws.on('close', cleanup);
  ws.on('error', cleanup);
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
        send(c.ws, { type: 'join_failed', reason: 'Server is full' });
        break;
      }
      // applied before any c.name read, including the default lobby-name fallback
      if (typeof msg.playerName === 'string' && msg.playerName.trim().length > 0) c.name = msg.playerName.slice(0, 24);
      leaveLobby(id);
      const lobbyId = nextLobbyId++;
      const name = (typeof msg.name === 'string' && msg.name.trim().length > 0) ? msg.name.slice(0, 32) : (c.name + "'s lobby");
      lobbies.set(lobbyId, { name, hostId: id, members: new Set([id]) });
      c.lobbyId = lobbyId;
      send(c.ws, { type: 'hosted', lobbyId, name });
      console.log(`[lobby] ${id} hosted "${name}" (#${lobbyId})`);
      break;
    }
    case 'list_lobbies': {
      const list = [...lobbies.keys()].map(lobbySummary).filter(Boolean);
      send(c.ws, { type: 'lobby_list', lobbies: list });
      break;
    }
    case 'join_lobby': {
      if (typeof msg.playerName === 'string' && msg.playerName.trim().length > 0) c.name = msg.playerName.slice(0, 24);
      const lobbyId = msg.lobbyId | 0;
      const l = lobbies.get(lobbyId);
      if (!l) {
        send(c.ws, { type: 'join_failed', reason: 'Lobby not found' });
        break;
      }
      if (l.members.size >= MAX_LOBBY_MEMBERS) {
        send(c.ws, { type: 'join_failed', reason: 'Lobby is full' });
        break;
      }
      leaveLobby(id);
      l.members.add(id);
      c.lobbyId = lobbyId;
      send(c.ws, { type: 'joined', lobbyId, name: l.name });
      console.log(`[lobby] ${id} joined "${l.name}" (#${lobbyId})`);
      break;
    }
    case 'leave_lobby': {
      leaveLobby(id);
      send(c.ws, { type: 'left' });
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
        if (mc) send(mc.ws, { type: 'chat', from: c.name, fromColor: c.nameColor, text });
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
      send(c.ws, {
        type: 'snapshot',
        players: all.filter((p) => p.id !== id).map(({ lastUpdate, ...rest }) => rest),
      });
    }
  }
}, 1000 / BROADCAST_HZ);

// ws has no built-in idle timeout (unlike a raw socket's setTimeout) -- a
// standard ping/pong heartbeat instead, terminating anything that didn't
// answer the previous ping.
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) { ws.terminate(); return; }
    ws.isAlive = false;
    try { ws.ping(); } catch (e) { /* already gone */ }
  });
}, HEARTBEAT_MS);

process.on('uncaughtException', (e) => console.error('[!] uncaught exception:', e));
process.on('unhandledRejection', (e) => console.error('[!] unhandled rejection:', e));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`[i] ${sig} received, shutting down`);
    wss.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}

console.log(`IGTAP multiplayer relay (WebSocket) listening on :${PORT}`);
