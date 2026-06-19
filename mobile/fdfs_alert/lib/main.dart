import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:moovaa/core/network/fcm_service.dart';
import 'package:moovaa/moovaa.dart';

import 'firebase_options.dart';

/// Host entry: Firebase config + FCM background handler, then MOOVAA package UI.
Future<void> main() async {
  if (!kIsWeb) {
    MoovaaConfig.firebaseOptions = DefaultFirebaseOptions.currentPlatform;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await MoovaaBootstrap.run();
}
