import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'notification_router.dart';

/// Initialises Firebase exactly once and returns the FCM registration token.
///
/// Returns null on web (FCM not used) or when the device has no Play Services.
/// Throws [FcmBootstrapException] with a human-readable message when
/// setup fails so the splash screen can show it to the user.
class FcmBootstrapException implements Exception {
  FcmBootstrapException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FcmBootstrap {
  static bool _initialized = false;

  static Future<String?> initializeAndGetToken() async {
    if (kIsWeb) return null;

    try {
      if (!_initialized) {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        _initialized = true;
      }

      await NotificationRouter.install();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
        'FCM permission: ${settings.authorizationStatus.name}',
      );

      final token = await messaging.getToken();
      debugPrint('FCM token length: ${token?.length ?? 0}');
      return token;
    } on FirebaseException catch (e) {
      throw FcmBootstrapException(
        'Firebase init failed (${e.code}): ${e.message}\n'
        'Check google-services.json and debug SHA-1 in Firebase Console.',
      );
    } catch (e) {
      throw FcmBootstrapException('FCM init error: $e');
    }
  }
}
