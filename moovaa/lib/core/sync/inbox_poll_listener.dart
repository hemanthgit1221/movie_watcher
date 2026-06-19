import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/notifications/notifications_screen.dart';
import '../../router/app_router.dart';
import '../../shared/providers/providers.dart';
import '../network/api_client.dart';

/// Polls `/notifications/inbox` while the app is in the foreground (web + mobile).
/// Shows in-app toasts for new booking-open and admin broadcast items.
class InboxPollListener extends ConsumerStatefulWidget {
  const InboxPollListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InboxPollListener> createState() => _InboxPollListenerState();
}

class _InboxPollListenerState extends ConsumerState<InboxPollListener>
    with WidgetsBindingObserver {
  Timer? _timer;
  final Set<String> _seenKeys = {};
  bool _primed = false;

  static const _pollInterval = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_pollInterval, (_) => _pollInbox(showToasts: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollInbox(showToasts: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollInbox(showToasts: true);
    }
  }

  String _itemKey(Map<String, dynamic> row) {
    final type = (row['type'] as String? ?? '').toLowerCase();
    final id = row['id'];
    return '$type-$id';
  }

  Future<void> _pollInbox({required bool showToasts}) async {
    final token = ref.read(accessTokenProvider);
    if (token == null || token.isEmpty) return;

    try {
      final api = ref.read(apiProvider);
      final rows = await api.getNotificationInbox();
      if (!mounted) return;

      final newItems = <Map<String, dynamic>>[];
      for (final row in rows) {
        final key = _itemKey(row);
        if (_seenKeys.contains(key)) continue;
        _seenKeys.add(key);
        if (_primed && showToasts) {
          newItems.add(row);
        }
      }
      _primed = true;

      if (!showToasts || newItems.isEmpty) return;

      final ctx = moovaaRootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      for (final row in newItems.reversed) {
        final type = (row['type'] as String? ?? '').toLowerCase();
        if (type == 'booking_open') {
          final watcherId = row['watcher_id'] as int?;
          final title = row['title'] as String? ?? 'Tickets OPEN';
          final body = row['body'] as String? ?? '';
          MoovaaToast.show(
            ctx,
            movieTitle: title.replaceFirst(RegExp(r'^Tickets OPEN — '), ''),
            theatre: body,
            city: '',
            onBook: () async {
              if (watcherId == null) return;
              final url = await api.resolveBookingUrlByWatcher(watcherId);
              if (url == null || url.isEmpty) return;
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          );
        } else if (type == 'admin_broadcast') {
          MoovaaToast.show(
            ctx,
            movieTitle: row['title'] as String? ?? 'MOOVAA',
            theatre: row['body'] as String? ?? '',
            city: '',
            onBook: () {},
          );
        }
      }
    } catch (e) {
      debugPrint('Inbox poll skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
