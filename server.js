// server.js
import express from "express";
import http from "http";
import { Server } from "socket.io";
import { nanoid } from "nanoid";
import rateLimit from "express-rate-limit";
import fs from "fs";
import path from "path";

const app = express();
app.set('trust proxy', 1);

const server = http.createServer(app);
const io = new Server(server);

const PORT = process.env.PORT || 3000;
const BASE_URL = process.env.BASE_URL || `http://localhost:${PORT}`;
const CHAT_PASSWORD = process.env.CHAT_PASSWORD;

// Ensure data folder
const DATA_DIR = path.join(process.cwd(), "data");
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

app.use(express.json());
app.use(express.static(path.join(process.cwd(), "public")));

const rooms = new Map();
// rooms: roomId -> { sessionId, name, creatorSocketId, expiresAt }

const createLimiter = rateLimit({ windowMs: 5000, max: 10 });

app.post('/api/create', createLimiter, (req, res) => {
  const name = (req.body?.name || 'Room').toString().slice(0, 48);
  const roomId = Math.floor(1000 + Math.random() * 9000).toString();
  const sessionId = nanoid(48);

  // لا يوجد وقت انتهاء إطلاقًا
  const ttlSeconds = null;
  const expiresAt = null;

  // لا نستخدم setTimeout نهائيًا
  rooms.set(roomId, { sessionId, name, creatorSocketId: null, expiresAt: null, timeoutObj: null });

  // create data file
  const filePath = path.join(DATA_DIR, `${roomId}.json`);
  if (!fs.existsSync(filePath)) fs.writeFileSync(filePath, JSON.stringify({ roomId, name, messages: [] }, null, 2));

  const joinUrl = `${BASE_URL}/room.html?roomId=${encodeURIComponent(roomId)}&sessionId=${encodeURIComponent(sessionId)}&name=${encodeURIComponent(name)}`;
  return res.json({ ok: true, roomId, sessionId, joinUrl, expiresAt });
});

app.post('/api/end', (req, res) => {
  const { roomId, sessionId } = req.body || {};
  if (!rooms.has(String(roomId))) return res.status(404).json({ ok: false, error: 'Not found' });
  const room = rooms.get(String(roomId));
  if (room.sessionId !== String(sessionId)) return res.status(403).json({ ok: false, error: 'Forbidden' });
  clearTimeout(room.timeoutObj);
  rooms.delete(roomId);
  io.to(roomId).emit('session_ended');
  return res.json({ ok: true });
});

app.get('/api/validate', (req, res) => {
  const { roomId, sessionId } = req.query;
  if (!roomId || !sessionId) return res.json({ ok: false });
  const room = rooms.get(String(roomId));
  if (!room) return res.json({ ok: false });
  if (room.sessionId !== String(sessionId)) return res.json({ ok: false });
  return res.json({ ok: true, name: room.name, expiresAt: room.expiresAt });
});

// serve list of messages (only if provide correct password)
app.get('/api/messages', (req, res) => {
  const { roomId, password } = req.query;
  if (!roomId) return res.status(400).json({ ok: false });
  if (String(password) !== CHAT_PASSWORD) return res.status(403).json({ ok: false, error: 'wrong password' });
  const filePath = path.join(DATA_DIR, `${roomId}.json`);
  if (!fs.existsSync(filePath)) return res.json({ ok: true, messages: [] });
  const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  return res.json({ ok: true, messages: data.messages || [] });
});

io.on('connection', (socket) => {
  socket.on('join', ({ roomId, sessionId, displayName, password }) => {
    const room = rooms.get(String(roomId));
    if (!room) { socket.emit('join_error', 'Room not found or expired'); return; }
    if (room.sessionId !== sessionId) { socket.emit('join_error', 'Invalid session token'); return; }
    if (String(password) !== CHAT_PASSWORD) { socket.emit('join_error', 'Wrong password'); return; }

    socket.join(roomId);
    socket.data.displayName = displayName || 'Guest';
// assign a consistent random color to this user
const colors = ['#007AFF', '#FF2D55', '#34C759', '#FF9500', '#AF52DE', '#5AC8FA', '#FFCC00'];
socket.data.color = colors[Math.floor(Math.random() * colors.length)];


    if (!room.creatorSocketId) room.creatorSocketId = socket.id;

    // load recent messages from disk and send to this client
    const filePath = path.join(DATA_DIR, `${roomId}.json`);
    if (fs.existsSync(filePath)) {
      try {
        const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        const recent = (data.messages || []).slice(-200);
        socket.emit('history', recent);
      } catch (e) { /* ignore */ }
    }

    socket.emit('joined', { roomId, name: room.name });
socket.to(roomId).emit('user_joined', { id: socket.id, name: socket.data.displayName, color: socket.data.color });
  });

  socket.on('message', ({ roomId, text }) => {
    if (!rooms.has(roomId)) return;
    const room = rooms.get(roomId);
const msg = { 
  id: nanoid(10), 
  from: socket.data.displayName || 'Guest', 
  text: String(text).slice(0, 2000), 
  at: Date.now(), 
  color: socket.data.color 
};

    // append to file
    const filePath = path.join(DATA_DIR, `${roomId}.json`);
    let data = { roomId, messages: [] };
    try {
      if (fs.existsSync(filePath)) data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (e) { }
    data.messages = data.messages || [];
    data.messages.push(msg);
    // cap
    if (data.messages.length > 5000) data.messages.splice(0, data.messages.length - 5000);
    try { fs.writeFileSync(filePath, JSON.stringify(data, null, 2)); } catch (e) { /* ignore write errors */ }

    io.to(roomId).emit('message', msg);
  });

  socket.on('end_session', ({ roomId, sessionId }) => {
    const room = rooms.get(roomId);
    if (!room) return;
    if (room.sessionId !== sessionId) { socket.emit('error_msg', 'Forbidden'); return; }
    clearTimeout(room.timeoutObj);
    rooms.delete(roomId);
    io.to(roomId).emit('session_ended');
  });
});

server.listen(PORT, () => console.log(`Server listening on ${PORT}`));
