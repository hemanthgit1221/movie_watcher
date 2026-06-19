# Notification service (decoupled from watcher)

Watcher enqueues `watcher_opened` events; **`notification_worker`** delivers FCM.

## Run

```powershell
cd notification_worker
pip install -e ../backend[fcm]
python main.py
```

Requires `REDIS_URL`, `DATABASE_URL`, `FCM_ENABLED=true`.

## Why split

- Watcher stays CPU/RAM bound (Playwright)
- Notification worker scales horizontally on push spikes
- Failed FCM retries do not block page checks

See [`notification_worker/main.py`](../../notification_worker/main.py).
