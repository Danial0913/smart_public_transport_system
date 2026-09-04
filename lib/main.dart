import 'package:flutter/material.dart';

import 'data/journey_notification_service.dart';
import 'data/local_storage_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.instance.initialise();
  try {
    await JourneyNotificationService.instance.initialise();
  } catch (error, stackTrace) {
    debugPrint('Notification startup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  runApp(const SmartTransportApp());
}

class SmartTransportApp extends StatelessWidget {
  const SmartTransportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Public Transport',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
