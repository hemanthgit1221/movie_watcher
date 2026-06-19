import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/notification_router.dart';
import '../../data/local/inbox_item.dart';
import '../../providers/inbox_providers.dart';
import '../../theme/moovaa_colors.dart';
import '../../theme/moovaa_spacing.dart';

enum _InboxFilter { all, unread }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _InboxFilter _filter = _InboxFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inboxListProvider.notifier).ensureLoaded();
    });
  }

  Future<void> _openItem(InboxItem item) async {
    await ref.read(inboxListProvider.notifier).markRead(item.id);
    final data = <String, String>{
      if (item.movieId != null) 'movie_id': item.movieId!,
      if (item.watcherId != null) 'watcher_id': item.watcherId!,
      if (item.theatre != null) 'theatre': item.theatre!,
      if (item.city != null) 'city': item.city!,
    };
    await NotificationRouter.openFromData(data);
  }

  Future<void> _bookNow(InboxItem item) async {
    final url = item.bookingUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open booking link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(inboxListProvider.notifier).markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MoovaaSpacing.md),
            child: SegmentedButton<_InboxFilter>(
              segments: const [
                ButtonSegment(value: _InboxFilter.all, label: Text('All')),
                ButtonSegment(value: _InboxFilter.unread, label: Text('Unread')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: inboxAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final filtered = _filter == _InboxFilter.unread
                    ? items.where((i) => !i.read).toList()
                    : items;
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(MoovaaSpacing.lg),
                      child: Text(
                        _filter == _InboxFilter.unread
                            ? 'No unread notifications'
                            : 'Notifications appear here when tickets open.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: MoovaaColors.textSecondary,
                            ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(inboxListProvider.notifier).refresh(),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      return _InboxCard(
                        item: item,
                        onTap: () => _openItem(item),
                        onBook: item.bookingUrl != null &&
                                item.bookingUrl!.isNotEmpty
                            ? () => _bookNow(item)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.onTap,
    this.onBook,
  });

  final InboxItem item;
  final VoidCallback onTap;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: MoovaaSpacing.md,
        vertical: MoovaaSpacing.xs,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(MoovaaSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: MoovaaColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_fire_department,
                  color: MoovaaColors.onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: MoovaaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!item.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: MoovaaColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.body),
                    Text(
                      _timeAgo(item.receivedAtIso),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: MoovaaColors.textSecondary,
                          ),
                    ),
                    if (onBook != null) ...[
                      const SizedBox(height: MoovaaSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: onBook,
                          child: const Text('Book now'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
