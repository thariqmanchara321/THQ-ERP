import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/pos_entry_screen.dart';
import 'services/app_log_service.dart';
import 'ui/v43_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogService().log(
      appKey: 'pos',
      error: details.exception,
      stack: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogService().log(
      appKey: 'pos',
      error: error,
      stack: stack,
      severity: 'fatal',
    );
    return true;
  };

  runApp(const ThqPosApp());
}

class ThqPosApp extends StatelessWidget {
  const ThqPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THQ POS',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ThqNotificationHost(
        child: NumericZeroAutoSelect(child: child ?? const SizedBox.shrink()),
      ),
      theme: UiDesignProfile.fallback('pos').theme(),
      home: const PosEntryScreen(),
    );
  }
}
