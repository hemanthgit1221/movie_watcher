import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../moovaa_config.dart';

// ═══════════════════════════════════════════════════════════════════
// MOOVAA FCM SERVICE
// Premium notification handling with deep-link routing
// ═══════════════════════════════════════════════════════════════════

// ─── Background handler (top-level, outside any class) ───────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = MoovaaConfig.firebaseOptions;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  }
  await MoovaaFCM.ensureInitialized();
  // Android already shows notification payload in tray when backgrounded/killed.
  if (defaultTargetPlatform == TargetPlatform.android &&
      message.notification != null) {
    return;
  }
  await MoovaaFCM._showLocalNotification(message);
}

// ─── Notification Channel Config ─────────────────────────────────────
const _kBookingChannelId = 'moovaa_booking_alerts';
const _kBookingChannelName = 'Booking Alerts';
const _kBookingChannelDesc = 'FDFS ticket availability notifications';

const _kReminderChannelId = 'moovaa_reminders';
const _kReminderChannelName = 'Release Reminders';
const _kReminderChannelDesc = 'Upcoming release day notifications';

// ─── FCM Service ─────────────────────────────────────────────────────
class MoovaaFCM {
  MoovaaFCM._();

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Called by onTap deep-link routing
  static Future<String?> Function(int watcherId)? resolveBookingUrl;
  static Function(String movieId)? onMovieTap;

  // ── Init ──────────────────────────────────────────────────────────
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _setupLocalNotifications();
  }

  static Future<void> init({
    required Future<String?> Function(int watcherId) resolveBookingUrlFn,
    required Function(String movieId) onMovie,
  }) async {
    resolveBookingUrl = resolveBookingUrlFn;
    onMovieTap = onMovie;
    await ensureInitialized();

    // Request permission
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
      criticalAlert: false, provisional: false,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // iOS foreground presentation
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false, badge: true, sound: false,
    );

    // Token
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token (${token?.length ?? 0} chars)');

    // Refresh token listener
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      debugPrint('FCM token refreshed');
      // TODO: POST /api/v1/devices/register with new token
    });

    // Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((msg) async {
      debugPrint('FCM foreground: ${msg.notification?.title}');
      await _showLocalNotification(msg);
      // Also show in-app toast if context available
    });

    // Notification tapped while app in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // App opened from terminated state via notification
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessageTap(initial);
  }

  // ── Local Notifications Setup ─────────────────────────────────────
  static Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // Create Android channels
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kBookingChannelId, _kBookingChannelName,
        description: _kBookingChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFF6B00),
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kReminderChannelId, _kReminderChannelName,
        description: _kReminderChannelDesc,
        importance: Importance.defaultImportance,
      ),
    );
  }

  static bool _isHighPriorityType(String type) =>
      type == 'booking_open' || type == 'admin_broadcast';

  static String _resolveTitle(RemoteMessage message, String type) {
    final notificationTitle = message.notification?.title?.trim();
    if (notificationTitle != null && notificationTitle.isNotEmpty) {
      return notificationTitle;
    }
    final dataTitle = message.data['title']?.toString().trim();
    if (dataTitle != null && dataTitle.isNotEmpty) return dataTitle;
    if (type == 'booking_open') return '🔥 Tickets LIVE!';
    if (type == 'admin_broadcast') return 'MOOVAA';
    return '📅 Releasing Tomorrow';
  }

  static String _resolveBody(RemoteMessage message) {
    final notificationBody = message.notification?.body?.trim();
    if (notificationBody != null && notificationBody.isNotEmpty) {
      return notificationBody;
    }
    final dataBody = message.data['body']?.toString().trim();
    if (dataBody != null && dataBody.isNotEmpty) return dataBody;
    return _buildBody(message.data);
  }

  // ── Show Local Notification ───────────────────────────────────────
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final data = message.data;
    final type = data['type']?.toString() ?? 'booking_open';
    final isHighPriority = _isHighPriorityType(type);

    final title = _resolveTitle(message, type);
    final body = _resolveBody(message);

    final androidDetails = AndroidNotificationDetails(
      isHighPriority ? _kBookingChannelId : _kReminderChannelId,
      isHighPriority ? _kBookingChannelName : _kReminderChannelName,
      channelDescription:
          isHighPriority ? _kBookingChannelDesc : _kReminderChannelDesc,
      importance:
          isHighPriority ? Importance.max : Importance.defaultImportance,
      priority: isHighPriority ? Priority.max : Priority.defaultPriority,
      playSound: true,
      enableVibration: isHighPriority,
      color: const Color(0xFFFF6B00),
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        body,
        summaryText: data['theatre']?.toString() ?? '',
      ),
      category: isHighPriority
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent: type == 'booking_open',
      ticker: title,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: darwinDetails),
      payload: data['movie_id'] ?? data['watcher_id'] ?? '',
    );
  }

  static String _buildBody(Map<String, dynamic> data) {
    final movie = data['movie'] ?? data['movie_title'] ?? '';
    final theatre = data['theatre'] ?? data['theatre_name'] ?? '';
    final city = data['city'] ?? '';
    if (theatre.isNotEmpty) return '$movie\n$theatre${city.isNotEmpty ? ' · $city' : ''}';
    return movie;
  }

  // ── Handle Taps ───────────────────────────────────────────────────
  static void _onLocalTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(
        (payload.startsWith('{'))
            ? (jsonDecode(payload) as Map)
            : {'movie_id': payload},
      );
      _handleNotificationData(
        data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      );
    } catch (_) {
      onMovieTap?.call(payload);
    }
  }

  static Future<void> _handleNotificationData(Map<String, dynamic> data) async {
    final watcherIdStr = data['watcher_id']?.toString() ?? '';
    final movieId = data['movie_id']?.toString() ?? '';

    if (watcherIdStr.isNotEmpty) {
      final watcherId = int.tryParse(watcherIdStr);
      if (watcherId != null && resolveBookingUrl != null) {
        final url = await resolveBookingUrl!(watcherId);
        if (url != null && url.isNotEmpty) {
          await _launchUrl(url);
          return;
        }
      }
    }

    if (movieId.isNotEmpty) {
      onMovieTap?.call(movieId);
    }
  }

  static void _handleMessageTap(RemoteMessage message) {
    Future.delayed(const Duration(milliseconds: 300), () {
      _handleNotificationData(message.data);
    });
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Token Getter ──────────────────────────────────────────────────
  static Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  // ── Badge management ──────────────────────────────────────────────
  static Future<void> clearBadge() async {
    await _local
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(badge: true);
    await _local.cancelAll();
  }
}
