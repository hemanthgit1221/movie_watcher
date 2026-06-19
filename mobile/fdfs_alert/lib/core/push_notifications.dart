import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/local/inbox_store.dart';
import '../firebase_options.dart';
import 'fcm_payload_codec.dart';
import 'notification_router.dart';
import 'storage/hive_boxes.dart';

/// Android channel id — must match AndroidManifest meta-data.
const kFdfsAlertsChannelId = 'fdfs_alerts';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

bool _localReady = false;

class PushNotifications {
  static Future<void> ensureFirebase() async {
    if (kIsWeb) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  static Future<void> init() async {
    if (kIsWeb || _localReady) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) async {
        await NotificationRouter.handleLocalNotificationPayload(
          response.payload,
        );
      },
    );

    const channel = AndroidNotificationChannel(
      kFdfsAlertsChannelId,
      'Ticket alerts',
      description: 'Booking opened notifications',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _localReady = true;
  }

  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
    if (kIsWeb) return;
    await init();

    final notification = message.notification;
    final title = notification?.title ??
        message.data['movie'] ??
        'FDFS Alert';
    final body = notification?.body ?? 'Tickets may be open';

    final payload = FcmPayloadCodec.encode(
      message.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );

    final id = message.hashCode & 0x7fffffff;

    await _local.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kFdfsAlertsChannelId,
          'Ticket alerts',
          channelDescription: 'Booking opened notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
    debugPrint('PushNotifications: showed local notification id=$id');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotifications.ensureFirebase();
  await openMoovaaHiveBoxes();
  await InboxStore().appendFromRemoteMessage(message);
  // Data-only messages: no system tray entry — show locally.
  if (message.notification == null && message.data.isNotEmpty) {
    await PushNotifications.showFromRemoteMessage(message);
  }
}
