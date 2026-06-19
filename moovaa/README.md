# MOOVAA — Cinematic FDFS Alert App

> **Never miss FDFS again.**  
> Real-time movie ticket alert platform for Indian cinema fans.

---

## What is MOOVAA?

MOOVAA is a **ticket-alert-first** app — NOT a streaming platform.

It monitors BookMyShow for theatre-specific FDFS (First Day First Show) booking
windows and instantly pushes an alert the moment seats go on sale.

```
Movie → Theatre → Alert → Push → Booking
```

---

## Project Structure

```
moovaa/
├── lib/
│   ├── main.dart                          ← Entry point, ProviderScope, theme
│   ├── core/
│   │   ├── theme/
│   │   │   ├── moovaa_theme.dart          ← Full design system (colors, type, gradients)
│   │   │   └── shared_widgets.dart        ← All reusable components
│   │   ├── network/
│   │   │   ├── api_client.dart            ← Dio, auth interceptor, MoovaaApi repo
│   │   │   └── fcm_service.dart           ← FCM init, notification channels, deep-link
│   │   └── utils/
│   │       └── performance.dart           ← Image cache, lazy loading, scroll physics
│   ├── router/
│   │   └── app_router.dart                ← GoRouter, ShellRoute, bottom nav shell
│   ├── shared/
│   │   └── providers/
│   │       └── providers.dart             ← Riverpod state (alerts, watchlist, movies)
│   └── features/
│       ├── onboarding/
│       │   └── onboarding_screen.dart     ← 3-slide FDFS onboarding with animations
│       ├── home/
│       │   └── home_screen.dart           ← Hero banner + poster carousels
│       ├── movies/
│       │   ├── movies_screen.dart         ← Searchable poster grid
│       │   └── movie_detail_screen.dart   ← Cinematic detail + Track CTA
│       ├── theatre/
│       │   └── theatre_bottom_sheet.dart  ← Premium theatre selector
│       ├── alerts/
│       │   └── alerts_screen.dart         ← Alert control center
│       ├── watchlist/
│       │   └── watchlist_screen.dart      ← Poster-heavy grid/list
│       ├── notifications/
│       │   └── notifications_screen.dart  ← In-app notification center + toast
│       └── profile/
│           └── profile_screen.dart        ← Settings, notif prefs, stats
└── pubspec.yaml
```

---

## Design System

### Color Palette

| Token               | Hex         | Usage                        |
|---------------------|-------------|------------------------------|
| `MColors.black`     | `#050505`   | AMOLED black                 |
| `MColors.bg`        | `#080808`   | App background               |
| `MColors.surface1`  | `#131313`   | Cards                        |
| `MColors.surface2`  | `#1A1A1A`   | Elevated cards               |
| `MColors.orange`    | `#FF6B00`   | Primary brand / CTA          |
| `MColors.openedTeal`| `#00D4AA`   | OPENED status / live alerts  |
| `MColors.textPrimary`| `#F5F5F5`  | Headings                     |
| `MColors.textSecondary`| `#AAAAAA`| Body text                    |

### Status Colors

| Status   | Color              | Background       |
|----------|--------------------|------------------|
| ACTIVE   | `#FF6B00` (orange) | `#1A0D00`        |
| OPENED   | `#00D4AA` (teal)   | `#001A14`        |
| PAUSED   | `#555555` (gray)   | `#111111`        |
| FAILED   | `#E53935` (red)    | `#1A0606`        |

### Typography Scale

| Style              | Size | Weight | Usage                |
|--------------------|------|--------|----------------------|
| `heroTitle`        | 38   | 800    | Onboarding, home hero|
| `movieTitle`       | 26   | 800    | Movie detail heading |
| `sectionTitle`     | 18   | 700    | Section headers      |
| `cardTitle`        | 16   | 700    | Card titles          |
| `bodyLg`           | 16   | 400    | Descriptions         |
| `bodyMd`           | 14   | 400    | Supporting text      |
| `label`            | 11   | 600    | Chips, tags          |
| `tag`              | 10   | 700    | Uppercase badges     |
| `cta`              | 15   | 700    | Button labels        |

---

## Key Components

### Shared Widgets (`shared_widgets.dart`)

| Widget             | Purpose                                      |
|--------------------|----------------------------------------------|
| `MShimmer`         | Animated skeleton loading placeholder        |
| `MCinematicPoster` | Network image with shimmer + error fallback  |
| `MOrangeButton`    | Primary CTA with gradient + glow shadow      |
| `MGhostButton`     | Secondary outlined button                    |
| `MStatusChip`      | Animated ACTIVE/OPENED/PAUSED status pill    |
| `MHypeTag`         | FDFS HOT / IMAX / Fan Rush badges            |
| `MSectionHeader`   | Section title + subtitle + optional action   |
| `MEmptyState`      | Cinematic empty state with icon + CTA        |
| `MErrorBanner`     | Inline error with retry                      |
| `MCountdown`       | Release countdown timer pill                 |
| `MActiveDot`       | Pulsing live indicator dot                   |
| `MTapScale`        | Press-scale gesture wrapper                  |
| `MStaggeredItem`   | Staggered list entrance animation            |
| `MAlertCard`       | Full premium alert card with pulse animation |
| `MPosterCard`      | Horizontal carousel poster card              |
| `MHorizontalSection`| Labelled horizontal scroll container       |

---

## Screens

### 1. Onboarding
3 full-screen slides with animated floating badges, pulsing glow circles,
cinematic gradient backgrounds. Final slide has pulsing orange CTA for
notification permission.

### 2. Home
- **Hero banner** — full-height backdrop with parallax-ready design, movie
  title in 38px/800 weight, hype tags, orange Track Now CTA.
- **FDFS Hot Picks** — horizontal poster carousel, 140×200 cards.
- **Your Alerts** — live alert cards with pulse animation.
- **Upcoming Releases** — smaller poster cards with countdown timers.
- **Top Theatres** — horizontal chip strip.

### 3. Movie Detail
- Large backdrop with parallax scroll effect.
- Poster + title composite overlay.
- Synopsis with expand/collapse.
- FDFS info strip with active monitoring state.
- Theatre preview list with quick-add.
- **Sticky orange "Track This Movie" CTA** — pulses until tapped.

### 4. Theatre Bottom Sheet
- 88% height modal.
- Search bar with live filtering.
- Filter pills (Favourites, IMAX, 4DX, LUXE).
- Multi-select tile rows with animated selection state.
- Active alert badges per theatre.
- "Lock In Alert" CTA with success animation.

### 5. Alerts
- Filter bar: All / Watching / Live Now / Paused.
- Live banner when opened alerts exist (pulsing teal).
- Full alert cards with poster, theatre, status glow.
- Swipe-to-dismiss with red reveal.
- "Book Now" orange pill CTA on OPENED alerts.

### 6. Watchlist
- Tab bar: Saved / Alerted.
- Grid/List toggle.
- 3-column poster grid with quick "+ Track" overlays.
- List view with Set Alert CTA per movie.

### 7. Notifications
- In-app notification center.
- Notification cards with dismiss swipe.
- Type-specific styles (LIVE = teal, Reminder = orange).
- Mark all read.
- `MoovaaToast.show()` overlay for foreground FCM messages.

### 8. Profile
- User avatar + stats.
- Notification toggles (Booking / Reminders / Hype).
- Preference menu (City, Languages, Theatres).
- App menu (Rate, Share, Version, Privacy).

---

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure Firebase

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=your-firebase-project
```

### 3. Run

```bash
# Android emulator
flutter run --dart-define=API_BASE=http://10.0.2.2:8000

# Physical device (replace with your LAN IP)
flutter run --dart-define=API_BASE=http://192.168.1.X:8000

# Release build
flutter build apk --dart-define=API_BASE=https://api.moovaa.app
```

### 4. Assets

Create these directories and add your files:

```bash
mkdir -p assets/images assets/icons assets/fonts
```

Download Inter font family from https://fonts.google.com/specimen/Inter
and place in `assets/fonts/`.

---

## Connecting to Backend

### Replace sample data with real API calls

1. **Inject `dioProvider`** into screens via Riverpod `ref.watch(dioProvider)`.
2. **Replace `_sample*` lists** in screens with `ref.watch(moviesProvider)`,
   `ref.watch(alertsProvider)`, etc.
3. **Wire `MoovaaFCM.init()`** in `main.dart` after Firebase init.
4. **Register device** on splash using `MoovaaApi.registerDevice()` and store
   token via `MoovaaStorage.instance.writeToken()`.

### FCM data payload format expected

```json
{
  "type": "booking_open",
  "watcher_id": "42",
  "movie": "Pushpa 3",
  "movie_id": "pushpa-3",
  "theatre": "AMB Cinemas Gachibowli",
  "city": "Hyderabad",
  "booking_url": "https://in.bookmyshow.com/...",
  "poster_url": "https://image.tmdb.org/..."
}
```

---

## MVP Rollout Strategy

### Phase 1 — Visual shell (Week 1)
- Apply `moovaa_theme.dart` to existing app
- Replace all `TextStyle` calls with `MTextStyles.*`
- Replace colors with `MColors.*`
- Ship: no behavior change, pure visual upgrade

### Phase 2 — Component swap (Week 2)
- Replace existing alert cards with `MAlertCard`
- Replace existing buttons with `MOrangeButton` / `MGhostButton`
- Add `MStatusChip` to all alert displays
- Add `MShimmer` to all loading states

### Phase 3 — Screen upgrades (Week 3)
- Drop in new `HomeScreen` (poster-first)
- Drop in new `AlertsScreen` (filter + swipe)
- Drop in new `WatchlistScreen` (grid view)

### Phase 4 — New screens (Week 4)
- `MovieDetailScreen` with theatre bottom sheet
- `OnboardingScreen` for new installs
- `NotificationsScreen` + `MoovaaToast`

### Phase 5 — Polish + perf (Week 5)
- `LazyPosterImage` for all poster lists
- `MRepaint` wrappers around heavy sections
- `MKeepAlive` for tab views
- Animation tuning

---

## Performance Notes

- All list screens use `SliverList` / `SliverGrid` — never `Column` in `ListView`
- Poster images use `cacheWidth`/`cacheHeight` at 2× device pixel ratio
- Image cache set to 100MB, 200 items via `MoovaaPerf.init()`
- Animations use `SingleTickerProviderStateMixin` — disposed on unmount
- `RepaintBoundary` wraps the hero banner and alert card lists
- `NoTransitionPage` for bottom nav tab switches (no animation overhead)
- `BouncingScrollPhysics` everywhere for natural iOS/Android feel
- Text scale clamped to 0.9–1.15 to prevent layout breaks on large-text devices

---

*Built with Flutter · Riverpod · GoRouter · Material 3*  
*MOOVAA — Never miss FDFS again.*
