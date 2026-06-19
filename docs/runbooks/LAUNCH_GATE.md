# MOOVAA Launch Gate Checklist

Minimum score **65/100** before any major FDFS release promotion.

## Infrastructure

- [ ] PostgreSQL primary running; SQLite not used in production
- [ ] Redis queue + notification worker healthy
- [ ] API readiness `/health/ready` returns `database: true`
- [ ] Grafana dashboards receiving watcher + API metrics

## Detection

- [ ] ≥20 BMS fixtures validated via `testing/compare_detectors.py`
- [ ] UNKNOWN rate alert configured (Telegram/webhook)
- [ ] Fallback selector bundle deployed

## Product

- [ ] Next.js admin can publish movies/theatres
- [ ] Flutter FCM tap resolves booking URL via API
- [ ] Watchlist persists server-side

## Load test (staging)

- [ ] 500 concurrent alert creates without 5xx
- [ ] 5k subscriber fan-out p95 &lt; 2s with queue enabled
