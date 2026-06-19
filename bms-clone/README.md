# BMS Clone — MOOVAA Test Harness

A local, pixel-accurate **BookMyShow clone** for testing the MOOVAA watcher engine
against controlled, repeatable page states — without touching real BMS.

---

## Quick Start

```bash
cd bms-clone
npm install        # first time only
npm start          # starts on http://localhost:4000
```

Open the **Dashboard** → `http://localhost:4000/dashboard`

---

## What's Included

### Server (`server.js`)
Express server on port **4000** serving:

| Route | Purpose |
|---|---|
| `GET /dashboard` | Admin control panel |
| `GET /bms/booking/:showtimeId` | The page the watcher monitors |
| `GET /api/state` | Full JSON snapshot |
| `GET /api/movies` | List / CRUD movies |
| `GET /api/theatres` | List / CRUD theatres |
| `GET /api/showtimes` | List / CRUD showtimes (enriched) |
| `PATCH /api/showtimes/:id/state` | Toggle a slot's state instantly |
| `GET /api/events` | SSE stream for real-time dashboard updates |

### Dashboard (`dashboard/index.html`)
- **Overview** — live state grid for all slots with instant state toggles
- **Showtimes** — add/delete showtimes, per-row state selectors, copy watcher URLs
- **Movies** — create/delete movies
- **Theatres** — create/delete theatre venues
- **Scenarios** — one-click presets: ALL OPEN, ALL SOLD OUT, ALL CAPTCHA, MIXED, etc.
- **Watcher URLs** — generate `.env.test` snippet with all booking URLs

### Renderer (`renderer.js`)
Generates **pixel-accurate BMS HTML** for every state. Each page contains exactly
the DOM selectors that `watcher/engine/detector/bundles/v1_0_0/default.yaml` looks for:

| State | Key selectors present |
|---|---|
| `OPEN` | `.booking-flow`, `.seat-map`, `.showtime`, `.timings`, "Proceed to pay", "Choose seats" |
| `SOLD_OUT` | "sold out" |
| `NOT_OPEN` | "Bookings are not open", "Coming soon", "Notify Me" |
| `CAPTCHA` | `.g-recaptcha`, "captcha challenge", "captcha.*verification" |
| `LOADING` | `.loading-spinner`, `.skeleton-loader`, "Loading showtimes", "please wait" |
| `MAINTENANCE` | "venue not found", "could not find this venue" |
| `PARTIAL_OPEN` | `.booking-flow`, `.timings`, "Limited availability" |
| `REGIONAL_TA` | Tamil text + "Bookings are not open" |
| `REGIONAL_TE` | Telugu text + "Bookings are not open" |
| `FAILED_CONFIG` | "venue not found", "invalid venue" |
| `UNKNOWN` | "lorem ipsum", "data-missing", "unrecognized layout" |

---

## Connecting the Watcher

1. Start BMS clone: `npm start`
2. In your watcher DB, set `watcher.booking_url` to one of:
   ```
   http://localhost:4000/bms/booking/s1
   http://localhost:4000/bms/booking/s2
   ... (shown in Dashboard → Watcher URLs)
   ```
3. Copy `.env.test` settings to your `.env` (fast polling, dry_run=false)
4. Start the watcher as normal — it will now monitor your local BMS clone

---

## Selector Verification

All 11 states have been verified against `default.yaml` v1.0.0 selectors:
```
✅ OPEN         → booking-flow, seat-map, Proceed to pay, Choose seats, showtime
✅ NOT_OPEN     → Bookings are not open, Coming soon, Notify Me
✅ SOLD_OUT     → sold out
✅ PARTIAL_OPEN → booking-flow, timings, Limited availability
✅ CAPTCHA      → g-recaptcha, captcha challenge
✅ MAINTENANCE  → venue not found, could not find this venue
✅ LOADING      → loading-spinner, skeleton-loader, Loading showtimes
✅ REGIONAL_TA  → Tamil text + not open signal
✅ REGIONAL_TE  → Telugu text + not open signal
✅ FAILED_CONFIG→ venue not found, invalid venue
✅ UNKNOWN      → lorem ipsum, data-missing
```

---

## Test Scenarios (Dashboard → Scenarios tab)

| Scenario | What it tests |
|---|---|
| All OPEN | Watcher should fire alerts for every slot |
| All SOLD_OUT | Watcher must NOT alert |
| All NOT_OPEN | NOT_OPEN detection + no false positives |
| CAPTCHA Wall | CAPTCHA detection + automatic pause logic |
| PARTIAL_OPEN | Partial availability detection |
| Maintenance Mode | FAILED_CONFIG signal detection |
| LOADING State | Loading / skeleton detection |
| Regional Tamil | Regional language UI handling |
| Regional Telugu | Regional language UI handling |
| Mixed Reality | All states at once — real-world simulation |
