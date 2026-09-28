import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import 'config/supabase_config.dart';
import 'screens/mobile_pos_entry_screen.dart';
import 'services/mobile_app_log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      MobileAppLogService().log(
        error: details.exception,
        stack: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      MobileAppLogService().log(
        error: error,
        stack: stack,
        severity: 'fatal',
      ),
    );
    return true;
  };

  runApp(const ThqMobilePosApp());
}

class ThqMobilePosApp extends StatelessWidget {
  const ThqMobilePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'THQ Mobile POS',
      builder: (context, child) => ThqMobileProductionFrame(
        child: ThqNotificationHost(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      theme: ThqMobileTheme.pos(),
      home: const MobilePosEntryScreen(),
    );
  }
}
