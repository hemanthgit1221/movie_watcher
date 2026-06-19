import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/moovaa_theme.dart';
import '../../core/theme/shared_widgets.dart';

// ═══════════════════════════════════════════════════════════════════
// MOOVAA NOTIFICATION UX
// ═══════════════════════════════════════════════════════════════════

// ─── Notification Model ───────────────────────────────────────────────
enum NotifType { bookingLive, reminder, hype }

class MNotification {
  final String id;
  final NotifType type;
  final String movieTitle;
  final String theatre;
  final String city;
  final int? watcherId;
  final String? bookingUrl;
  final DateTime receivedAt;
  final bool isRead;

  const MNotification({
    required this.id,
    required this.type,
    required this.movieTitle,
    required this.theatre,
    required this.city,
    this.watcherId,
    this.bookingUrl,
    required this.receivedAt,
    this.isRead = false,
  });

  MNotification copyWith({bool? isRead}) => MNotification(
    id: id, type: type, movieTitle: movieTitle,
    theatre: theatre, city: city, watcherId: watcherId, bookingUrl: bookingUrl,
    receivedAt: receivedAt, isRead: isRead ?? this.isRead,
  );
}

// ─── Notifications Screen ─────────────────────────────────────────────
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<MNotification> _notifs = [];
  bool _loading = true;
  String? _error;

  int get _unreadCount => _notifs.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInbox());
  }

  Future<void> _loadInbox() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final rows = await api.getNotificationInbox();
      if (!mounted) return;
      setState(() {
        _notifs = rows.map((j) {
          final sentAt = j['sent_at'] as String?;
          DateTime received = DateTime.now();
          if (sentAt != null) {
            try {
              received = DateTime.parse(sentAt);
            } catch (_) {}
          }
          final type = (j['type'] as String? ?? '').toLowerCase();
          if (type == 'booking_open') {
            return MNotification(
              id: 'booking-${j['id']}',
              type: NotifType.bookingLive,
              movieTitle: j['title'] as String? ?? 'Tickets OPEN',
              theatre: j['body'] as String? ?? '',
              city: '',
              watcherId: j['watcher_id'] as int?,
              bookingUrl: null,
              receivedAt: received,
            );
          }
          return MNotification(
            id: 'broadcast-${j['id']}',
            type: NotifType.hype,
            movieTitle: j['title'] as String? ?? 'MOOVAA',
            theatre: j['body'] as String? ?? '',
            city: '',
            watcherId: null,
            receivedAt: received,
          );
        }).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _markAllRead() => setState(() {
    for (int i = 0; i < _notifs.length; i++) {
      _notifs[i] = _notifs[i].copyWith(isRead: true);
    }
  });

  void _markRead(String id) => setState(() {
    final i = _notifs.indexWhere((n) => n.id == id);
    if (i != -1) _notifs[i] = _notifs[i].copyWith(isRead: true);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: MColors.bg,
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MColors.surface2, shape: BoxShape.circle,
                  border: Border.all(color: MColors.border, width: 0.5)),
                child: const Icon(Icons.arrow_back_ios_new, size: 15))),
            title: Row(children: [
              const Text('Notifications'),
              if (_unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MColors.activeBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MColors.activeBorder, width: 0.5)),
                  child: Text('$_unreadCount new',
                    style: MTextStyles.label.copyWith(color: MColors.orange))),
              ],
            ]),
            actions: [
              if (_unreadCount > 0)
                GestureDetector(
                  onTap: _markAllRead,
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text('Mark all read',
                      style: MTextStyles.label.copyWith(color: MColors.orange)))),
            ],
          ),

          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: MColors.orange),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MErrorBanner(
                    message: _error!,
                    onRetry: _loadInbox,
                  ),
                ),
              ),
            )
          else if (_notifs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: MEmptyState(
                icon: Icons.notifications_none_outlined,
                title: 'No notifications yet',
                subtitle: 'Set alerts on your favourite movies\nand we\'ll ping you the moment\nbookings open.',
                iconColor: MColors.orange,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => MStaggeredItem(
                    index: i, delay: 45,
                    child: NotificationCard(
                      notif: _notifs[i],
                      onTap: () => _handleTap(_notifs[i]),
                      onDismiss: () => setState(() => _notifs.removeAt(i)),
                    ),
                  ),
                  childCount: _notifs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleTap(MNotification n) async {
    _markRead(n.id);
    if (n.type == NotifType.bookingLive) {
      String? url = n.bookingUrl;
      if (url == null && n.watcherId != null) {
        try {
          final api = ref.read(apiProvider);
          url = await api.resolveBookingUrlByWatcher(n.watcherId!);
        } catch (_) {
          url = null;
        }
      }
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    }
  }
}

// ─── Notification Card ────────────────────────────────────────────────
class NotificationCard extends StatefulWidget {
  const NotificationCard({
    super.key,
    required this.notif,
    required this.onTap,
    required this.onDismiss,
  });
  final MNotification notif;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    if (!widget.notif.isRead && widget.notif.type == NotifType.bookingLive) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  bool get _isLive => widget.notif.type == NotifType.bookingLive;
  bool get _isUnread => !widget.notif.isRead;

  Color get _accentColor {
    switch (widget.notif.type) {
      case NotifType.bookingLive: return MColors.openedTeal;
      case NotifType.reminder: return MColors.orange;
      case NotifType.hype: return MColors.orange;
    }
  }

  String get _typeLabel {
    switch (widget.notif.type) {
      case NotifType.bookingLive: return '🔥 TICKETS LIVE';
      case NotifType.reminder: return '📅 RELEASING TOMORROW';
      case NotifType.hype: return '⚡ HYPE ALERT';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('notif_${widget.notif.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: MColors.failedBg,
          borderRadius: MRadius.cardBorder,
          border: Border.all(color: MColors.failedRed.withOpacity(0.3), width: 0.5)),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.delete_outline, color: MColors.failedRed, size: 22),
          SizedBox(height: 4),
          Text('Clear', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: MColors.failedRed)),
        ]),
      ),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => MTapScale(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _isLive && _isUnread ? MColors.openedBg : MColors.surface1,
              borderRadius: MRadius.cardBorder,
              border: Border.all(
                color: _isUnread
                    ? _accentColor.withOpacity(_isLive ? 0.3 + 0.2 * _pulse.value : 0.25)
                    : MColors.border,
                width: _isUnread ? 1 : 0.5),
              boxShadow: _isUnread && _isLive
                  ? [BoxShadow(
                      color: _accentColor.withOpacity(0.08 + 0.06 * _pulse.value),
                      blurRadius: 16, spreadRadius: -4)]
                  : null,
            ),
            child: child,
          ),
        ),
        child: Column(children: [
          // Top accent bar for unread live
          if (_isUnread && _isLive)
            Container(height: 2, decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _accentColor.withOpacity(0.9), Colors.transparent]),
              borderRadius: const BorderRadius.vertical(top: MRadius.lg))),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Icon
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _accentColor.withOpacity(0.25), width: 0.5)),
                child: Icon(
                  _isLive ? Icons.confirmation_number_outlined
                    : widget.notif.type == NotifType.reminder
                        ? Icons.calendar_today_outlined
                        : Icons.local_fire_department_outlined,
                  size: 20, color: _accentColor)),

              const SizedBox(width: 14),

              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Type label
                Text(_typeLabel, style: MTextStyles.tag.copyWith(
                  color: _accentColor, fontSize: 10)),
                const SizedBox(height: 5),

                // Movie title
                Text(widget.notif.movieTitle, style: MTextStyles.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 3),

                // Theatre / body
                if (widget.notif.theatre.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.theaters, size: 11, color: MColors.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(child: Text(
                      '${widget.notif.theatre} · ${widget.notif.city}',
                      style: MTextStyles.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ])
                else if (widget.notif.type == NotifType.hype)
                  Text('Trending — track it now before it sells out',
                    style: MTextStyles.bodySm),

                const SizedBox(height: 10),

                Row(children: [
                  // Time
                  Text(_timeAgo(widget.notif.receivedAt),
                    style: MTextStyles.bodySm.copyWith(fontSize: 11)),
                  const Spacer(),
                  // CTA
                  if (_isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: MGradients.orangeButton,
                        borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Book Now', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: MColors.black)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 11, color: MColors.black),
                      ])),
                  if (!_isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: MColors.orangeDim,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: MColors.orangeBorder, width: 0.5)),
                      child: Text('View', style: MTextStyles.label.copyWith(color: MColors.orange))),
                ]),
              ])),

              // Unread dot
              if (_isUnread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: MActiveDot(size: 7, color: _accentColor)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── In-App Notification Toast ────────────────────────────────────────
/// Call this from FCM foreground message handler
class MoovaaToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String movieTitle,
    required String theatre,
    required String city,
    required VoidCallback onBook,
  }) {
    _current?.remove();
    _current = null;

    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        movieTitle: movieTitle,
        theatre: theatre,
        city: city,
        onBook: () { _current?.remove(); _current = null; onBook(); },
        onDismiss: () { _current?.remove(); _current = null; },
      ),
    );

    _current = entry;
    Overlay.of(context).insert(entry);

    // Auto-dismiss after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (_current == entry) { _current?.remove(); _current = null; }
    });
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.movieTitle, required this.theatre,
    required this.city, required this.onBook, required this.onDismiss,
  });
  final String movieTitle, theatre, city;
  final VoidCallback onBook, onDismiss;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slide = Tween(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16, right: 16,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MColors.surface2,
                borderRadius: MRadius.cardBorder,
                border: Border.all(color: MColors.openedTeal.withOpacity(0.4), width: 1),
                boxShadow: MShadows.tealGlow(intensity: 0.6) + MShadows.card,
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: MColors.openedBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MColors.openedTeal.withOpacity(0.4), width: 0.5)),
                  child: const Icon(Icons.confirmation_number_outlined,
                    size: 19, color: MColors.openedTeal)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const MActiveDot(size: 6, color: MColors.openedTeal),
                      const SizedBox(width: 6),
                      Text('🔥 TICKETS LIVE',
                        style: MTextStyles.tag.copyWith(color: MColors.openedTeal, fontSize: 10)),
                    ]),
                    const SizedBox(height: 3),
                    Text(widget.movieTitle, style: MTextStyles.cardTitle.copyWith(fontSize: 14)),
                    const SizedBox(height: 1),
                    Text('${widget.theatre} · ${widget.city}',
                      style: MTextStyles.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
                const SizedBox(width: 10),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  MTapScale(
                    onTap: widget.onBook,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: MGradients.orangeButton,
                        borderRadius: BorderRadius.circular(20)),
                      child: const Text('Book', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800, color: MColors.black)))),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(Icons.close, size: 14, color: MColors.textDisabled)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
