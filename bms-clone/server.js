'use strict';
/**
 * server.js — BMS Clone Express server (port 7358).
 *
 * Routes:
 *   GET  /                          → SPA (index.html with injected data)
 *   GET  /dashboard                 → Admin dashboard
 *   GET  /api/state                 → Full JSON snapshot
 *   GET  /api/movies                → List movies
 *   POST /api/movies                → Create movie
 *   PUT  /api/movies/:id            → Update movie
 *   PATCH /api/movies/:id/status    → Set status (coming_soon|now_showing)
 *   DELETE /api/movies/:id          → Delete movie
 *   GET  /api/theaters              → List theaters
 *   POST /api/theaters              → Create theater
 *   PUT  /api/theaters/:id          → Update theater
 *   DELETE /api/theaters/:id        → Delete theater
 *   GET  /api/showtimes             → List showtimes (with movie/theater enrichment)
 *   POST /api/showtimes             → Create showtime
 *   PUT  /api/showtimes/:id         → Update showtime
 *   PATCH /api/showtimes/:id/status → Set slot status (available|fast_filling|sold_out)
 *   DELETE /api/showtimes/:id       → Delete showtime
 *   GET  /api/events                → SSE stream for live dashboard updates
 */

const express = require('express');
const path    = require('path');
const fs      = require('fs');
const cors    = require('cors');
const store   = require('./store');

const PORT = 7358;
const app  = express();

app.use(cors());
app.use(express.json());

/* ── SSE clients ─────────────────────────────────────────────────────────── */
const _clients = new Set();

function broadcast(event, data) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of _clients) {
    try { res.write(payload); } catch (_) { _clients.delete(res); }
  }
}

store.setEmitter(broadcast);

/* ── SSE endpoint ────────────────────────────────────────────────────────── */
app.get('/api/events', (req, res) => {
  res.set({
    'Content-Type':  'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection':    'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders();
  res.write(': connected\n\n');

  const ping = setInterval(() => {
    try { res.write(': ping\n\n'); } catch (_) {}
  }, 20_000);

  _clients.add(res);
  req.on('close', () => { _clients.delete(res); clearInterval(ping); });
});

/* ── SPA — serve index.html with __BMS_DATA__ injected ──────────────────── */
const SPA_TEMPLATE = path.join(__dirname, 'public', 'index.html');

function serveSPA(req, res) {
  const tpl  = fs.readFileSync(SPA_TEMPLATE, 'utf8');
  const data = JSON.stringify(store.getState());
  const html = tpl.replace('/* __BMS_DATA__ */', `window.__BMS_DATA__ = ${data};`);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-BMS-Clone', 'true');
  res.send(html);
}

// Dashboard
app.get('/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'dashboard', 'index.html'));
});

// All other GETs → SPA (hash routes never hit server, but catch any stray GET /)
app.get('/', serveSPA);
app.get('/index.html', serveSPA);

/* ═══════════════════════════════════════════════════════════════════════════
   REST API
   ═══════════════════════════════════════════════════════════════════════════ */

/* ── State ─────────────────────────────────────────────────────────────────*/
app.get('/api/state', (req, res) => {
  res.json(store.getState());
});

/* ── Movies ────────────────────────────────────────────────────────────────*/
app.get('/api/movies', (req, res) => {
  res.json(store.getMovies());
});

app.get('/api/movies/:id', (req, res) => {
  const m = store.getMovie(req.params.id);
  if (!m) return res.status(404).json({ error: 'Movie not found' });
  res.json(m);
});

app.post('/api/movies', (req, res) => {
  const movie = store.createMovie(req.body);
  res.status(201).json(movie);
});

app.put('/api/movies/:id', (req, res) => {
  const m = store.updateMovie(req.params.id, req.body);
  if (!m) return res.status(404).json({ error: 'Movie not found' });
  res.json(m);
});

app.patch('/api/movies/:id/status', (req, res) => {
  const { status } = req.body;
  const allowed = ['coming_soon', 'now_showing'];
  if (!allowed.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${allowed.join(', ')}` });
  }
  const m = store.setMovieStatus(req.params.id, status);
  if (!m) return res.status(404).json({ error: 'Movie not found' });
  res.json(m);
});

app.delete('/api/movies/:id', (req, res) => {
  const ok = store.deleteMovie(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Movie not found' });
  res.json({ deleted: req.params.id });
});

/* ── Theaters ──────────────────────────────────────────────────────────────*/
app.get('/api/theaters', (req, res) => {
  const { city } = req.query;
  let list = store.getTheaters();
  if (city) list = list.filter(t => t.city.toLowerCase() === city.toLowerCase());
  res.json(list);
});

app.post('/api/theaters', (req, res) => {
  const t = store.createTheater(req.body);
  res.status(201).json(t);
});

app.put('/api/theaters/:id', (req, res) => {
  const t = store.updateTheater(req.params.id, req.body);
  if (!t) return res.status(404).json({ error: 'Theater not found' });
  res.json(t);
});

app.delete('/api/theaters/:id', (req, res) => {
  const ok = store.deleteTheater(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Theater not found' });
  res.json({ deleted: req.params.id });
});

/* ── Showtimes ─────────────────────────────────────────────────────────────*/
app.get('/api/showtimes', (req, res) => {
  const { movie_id, city, date, language } = req.query;
  const list = store.getEnrichedShowtimes().filter(s => {
    if (movie_id  && s.movie_id  !== movie_id)  return false;
    if (city      && s.city.toLowerCase() !== city.toLowerCase()) return false;
    if (date      && s.date      !== date)      return false;
    if (language  && s.language  !== language)  return false;
    return true;
  });
  res.json(list);
});

app.post('/api/showtimes', (req, res) => {
  const s = store.createShowtime(req.body);
  res.status(201).json(s);
});

app.put('/api/showtimes/:id', (req, res) => {
  const s = store.updateShowtime(req.params.id, req.body);
  if (!s) return res.status(404).json({ error: 'Showtime not found' });
  res.json(s);
});

app.patch('/api/showtimes/:id/status', (req, res) => {
  const { status } = req.body;
  const allowed = ['available', 'fast_filling', 'sold_out'];
  if (!allowed.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${allowed.join(', ')}` });
  }
  const s = store.setShowtimeStatus(req.params.id, status);
  if (!s) return res.status(404).json({ error: 'Showtime not found' });
  res.json(s);
});

// Bulk status update: set all showtimes for a movie+city+date to a status
app.patch('/api/showtimes/bulk/status', (req, res) => {
  const { movie_id, city, date, language, status } = req.body;
  const allowed = ['available', 'fast_filling', 'sold_out'];
  if (!allowed.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${allowed.join(', ')}` });
  }
  const list = store.getShowtimesFor({ movieId: movie_id, city, date, language });
  const updated = list.map(s => store.setShowtimeStatus(s.id, status)).filter(Boolean);
  res.json({ updated: updated.length, showtimes: updated });
});

app.delete('/api/showtimes/:id', (req, res) => {
  const ok = store.deleteShowtime(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Showtime not found' });
  res.json({ deleted: req.params.id });
});

/* ── Start ─────────────────────────────────────────────────────────────────*/
app.listen(PORT, '127.0.0.1', () => {
  const state = store.getState();
  const lines = [
    '',
    '╔══════════════════════════════════════════════════════════════╗',
    '║        🎬  BMS CLONE SERVER — MOOVAA TEST HARNESS            ║',
    '╠══════════════════════════════════════════════════════════════╣',
    `║  Dashboard:  http://127.0.0.1:${PORT}/dashboard               ║`,
    `║  SPA:        http://127.0.0.1:${PORT}/                        ║`,
    `║  API:        http://127.0.0.1:${PORT}/api/state               ║`,
    '╚══════════════════════════════════════════════════════════════╝',
    '',
  ];

  console.log(lines.join('\n'));

  console.log('  Movies loaded:');
  for (const m of state.movies) {
    const url1 = `http://127.0.0.1:${PORT}/#/movie/${m.slug}/${m.id}`;
    const url2 = `http://127.0.0.1:${PORT}/#/movies/mumbai/${m.slug}/${m.id}`;
    console.log(`  → [${m.status.padEnd(12)}] ${m.title}`);
    console.log(`       Short:  ${url1}`);
    console.log(`       Long:   ${url2}`);
  }
  console.log('');
  console.log(`  Theaters: ${state.theaters.length}   Showtimes: ${state.showtimes.length}`);
  console.log('');
});
