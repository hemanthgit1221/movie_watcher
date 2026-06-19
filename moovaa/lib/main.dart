import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/network/fcm_service.dart';
import 'firebase_options.dart';
import 'moovaa_app.dart';
import 'moovaa_config.dart';

/// Standalone entry when running the `moovaa` package directly.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MoovaaConfig.firebaseOptions = DefaultFirebaseOptions.currentPlatform;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await MoovaaBootstrap.run();
}
