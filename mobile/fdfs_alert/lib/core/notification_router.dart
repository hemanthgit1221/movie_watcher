import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/local/inbox_store.dart';
import 'booking_url_resolver.dart';
import 'fcm_payload_codec.dart';
import 'push_notifications.dart';

/// FCM + local notification routing (Phase 6).
///
/// Call [install] AFTER [FcmBootstrap.initializeAndGetToken] has succeeded.
class NotificationRouter {
  static bool _installed = false;
  static GoRouter? _router;

  static void bindRouter(GoRouter router) {
    _router = router;
  }

  static Future<void> install() async {
    if (kIsWeb || _installed) return;
    _installed = true;
    try {
      await PushNotifications.init();
      FirebaseMessaging.onMessage.listen((message) async {
        await InboxStore().appendFromRemoteMessage(message);
        await PushNotifications.showFromRemoteMessage(message);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        await _openFromMessage(initial);
      }
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
    } catch (e) {
      debugPrint('NotificationRouter install skipped: $e');
    }
  }

  static Future<void> _openFromMessage(RemoteMessage message) async {
    await openFromData(
      message.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  /// Tap handler — navigates to movie detail or opens booking via server-resolved URL.
  static bool _isStaleNotification(Map<String, String> data) {
    final sent = data['sent_at']?.trim();
    if (sent == null || sent.isEmpty) return false;
    final at = DateTime.tryParse(sent);
    if (at == null) return false;
    return DateTime.now().toUtc().difference(at.toUtc()).inMinutes > 15;
  }

  static Future<void> openFromData(Map<String, String> data) async {
    if (_isStaleNotification(data)) {
      debugPrint(
        'Notification may be stale (>15m since send). Seats may no longer be available.',
      );
    }
    final movieId = data['movie_id']?.trim();
    final watcherIdStr = data['watcher_id']?.trim();
    if (watcherIdStr != null && watcherIdStr.isNotEmpty) {
      await InboxStore().markReadByWatcherId(watcherIdStr);
    }

    if (watcherIdStr != null && watcherIdStr.isNotEmpty) {
      final watcherId = int.tryParse(watcherIdStr);
      if (watcherId != null) {
        final url = await BookingUrlResolver.fromWatcherId(watcherId);
        if (url != null && url.isNotEmpty) {
          await _launchBookingUrl(url);
          return;
        }
      }
    }

    if (movieId != null && movieId.isNotEmpty && _router != null) {
      _router!.go('/movie/$movieId');
      return;
    }
  }

  static Future<void> handleLocalNotificationPayload(String? payload) async {
    final data = FcmPayloadCodec.decode(payload);
    if (data.isEmpty) return;
    await openFromData(data);
  }

  static Future<void> _launchBookingUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
