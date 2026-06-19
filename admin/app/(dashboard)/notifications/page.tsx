"use client";

import { useEffect, useMemo, useState } from "react";
import { Modal } from "@/components/Modal";
import {
  createNotification,
  listNotifications,
  previewNotification,
  resendNotification,
} from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useToast } from "@/components/Toast";

type NotifRow = Awaited<ReturnType<typeof listNotifications>>[number];

export default function NotificationsPage() {
  const { authenticated } = useAuth();
  const { show: toast } = useToast();
  const [rows, setRows] = useState<NotifRow[]>([]);
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [previewCount, setPreviewCount] = useState<number | null>(null);
  const [pushEnabled, setPushEnabled] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [saving, setSaving] = useState(false);

  function load() {
    if (!authenticated) return;
    listNotifications()
      .then(setRows)
      .catch((e) => setError(e instanceof Error ? e.message : "Failed to load"));
  }

  useEffect(() => {
    load();
  }, [authenticated]);

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    if (!q) return rows;
    return rows.filter(
      (r) =>
        r.title.toLowerCase().includes(q) || r.description.toLowerCase().includes(q)
    );
  }, [rows, search]);

  function resetModal() {
    setTitle("");
    setDescription("");
    setImageUrl("");
    setPreviewCount(null);
    setConfirmed(false);
    setError("");
  }

  async function handlePreview() {
    if (!title.trim() || !description.trim()) {
      setError("Title and description are required");
      return;
    }
    setSaving(true);
    setError("");
    setConfirmed(false);
    try {
      const p = await previewNotification({
        title,
        description,
        image_url: imageUrl || undefined,
      });
      setPreviewCount(p.eligible_count + (p.in_app_count ?? 0));
      setPushEnabled(p.push_enabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Preview failed");
    } finally {
      setSaving(false);
    }
  }

  async function handleSend() {
    if (!confirmed) {
      setError("Check the confirmation box after previewing recipient count");
      return;
    }
    setSaving(true);
    setError("");
    try {
      const result = await createNotification({
        title,
        description,
        image_url: imageUrl || undefined,
      });
      setModalOpen(false);
      resetModal();
      load();
      const inApp = result.in_app_count ?? 0;
      if (result.sent_count === 0 && result.eligible_count === 0) {
        toast(
          inApp > 0
            ? `In-app feed updated for ${inApp} web/session user(s). Open MOOVAA in the browser to see it.`
            : result.push_enabled
              ? "Saved to in-app feed. 0 push devices — use Android/iOS app with FCM for phone alerts."
              : "Saved to in-app feed. Push disabled (FCM_ENABLED=false)."
        );
      } else {
        toast(
          `Push: ${result.sent_count}/${result.eligible_count} · In-app: ${inApp} web/session user(s)`
        );
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Send failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <div className="page-header">
        <div className="page-header-left">
          <h1 className="page-title">Notifications</h1>
          <p className="page-subtitle">Broadcast push notifications to your subscribed devices.</p>
        </div>
        <button
          type="button"
          className="btn-orange"
          onClick={() => {
            resetModal();
            setModalOpen(true);
          }}
        >
          ️ + New Notification
        </button>
      </div>
      {error && <div className="error-banner">⚠️ {error}</div>}
      <div className="table-toolbar">
        <div className="table-meta">
          <span>Showing</span>
          <span className="table-meta-count">{filtered.length}</span>
          <span>of {rows.length} notifications</span>
        </div>
        <div className="search-wrap">
          <span className="search-icon">🔍</span>
          <input
            className="search-input"
            placeholder="Search notifications…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>
      <div className="table-panel">
        <table className="data-table">
          <thead>
            <tr>
              <th>Image</th>
              <th>Title</th>
              <th>Description</th>
              <th>Sent</th>
              <th>Status</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((n) => (
              <tr key={n.id}>
                <td>
                  {n.image_url ? (
                    <img src={n.image_url} alt="" className="notif-thumb" />
                  ) : (
                    <div className="notif-placeholder">NO IMAGE</div>
                  )}
                </td>
                <td>
                  <span style={{ fontWeight: 600 }}>{n.title}</span>
                </td>
                <td style={{ maxWidth: 320, color: "var(--text-secondary)", fontSize: "0.85rem" }}>{n.description}</td>
                <td>
                  <span style={{ fontWeight: 700, color: n.sent_count > 0 ? "var(--orange)" : "var(--muted)" }}>
                    {n.sent_count}
                  </span>
                </td>
                <td>
                  <span className={`badge ${n.status === "sent" ? "badge-green" : n.status === "pending" ? "badge-orange" : "badge-gray"}`}>
                    {n.status}
                  </span>
                </td>
                <td>
                  <button
                    type="button"
                    className="btn-icon edit"
                    title="Resend"
                    onClick={async () => {
                      if (!confirm(`Resend "${n.title}" to all eligible devices?`)) return;
                      try {
                        const r = await resendNotification(n.id);
                        toast(`Resent to ${r.sent_count} of ${r.eligible_count} devices`);
                        load();
                      } catch (e) {
                        setError(e instanceof Error ? e.message : "Resend failed");
                      }
                    }}
                  >
                    ↻
                  </button>
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td colSpan={6} style={{ textAlign: "center", color: "var(--muted)" }}>
                  No notifications yet
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <Modal
        title="Add Notification"
        open={modalOpen}
        onClose={() => {
          setModalOpen(false);
          resetModal();
        }}
      >
        <label>Title</label>
        <input value={title} onChange={(e) => setTitle(e.target.value)} />
        <label>Description</label>
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} />
        <label>Image URL (optional)</label>
        <div
          className="notif-placeholder"
          style={{ width: "100%", height: 120, marginBottom: "0.5rem" }}
        >
          {imageUrl ? (
            <img
              src={imageUrl}
              alt=""
              style={{ maxWidth: "100%", maxHeight: "100%", objectFit: "contain" }}
            />
          ) : (
            "NO IMAGE"
          )}
        </div>
        <input
          value={imageUrl}
          onChange={(e) => setImageUrl(e.target.value)}
          placeholder="https://..."
        />
        {previewCount !== null && (
          <p style={{ marginTop: "1rem", color: "var(--text)" }}>
            <strong>{previewCount}</strong> device(s) will receive push
            {pushEnabled ? "" : " (FCM disabled — in-app feed only)"}.
          </p>
        )}
        {previewCount !== null && (
          <label style={{ display: "flex", gap: "0.5rem", alignItems: "center", marginTop: "0.75rem" }}>
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
            />
            I confirm sending to {previewCount} device(s)
          </label>
        )}
        <div className="modal-footer">
          <button
            type="button"
            className="btn-secondary"
            onClick={() => {
              setModalOpen(false);
              resetModal();
            }}
          >
            Close
          </button>
          <button
            type="button"
            className="btn-secondary"
            onClick={handlePreview}
            disabled={saving}
          >
            {saving ? "…" : "Preview recipients"}
          </button>
          <button
            type="button"
            className="btn-orange"
            onClick={handleSend}
            disabled={saving || !confirmed}
          >
            {saving ? "Sending…" : "Send broadcast"}
          </button>
        </div>
      </Modal>
    </>
  );
}
