import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/client_entry_screen.dart';
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
      appKey: 'client',
      error: details.exception,
      stack: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogService().log(
      appKey: 'client',
      error: error,
      stack: stack,
      severity: 'fatal',
    );
    return true;
  };

  runApp(const ThqBusinessApp());
}

class ThqBusinessApp extends StatelessWidget {
  const ThqBusinessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THQ Business',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          NumericZeroAutoSelect(child: child ?? const SizedBox.shrink()),
      theme: UiDesignProfile.fallback('client').theme(),
      home: const ClientEntryScreen(),
    );
  }
}
