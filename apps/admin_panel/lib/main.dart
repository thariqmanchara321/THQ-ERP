import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/admin_dashboard.dart';
import 'screens/login_screen.dart';
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
    AdminAppLogService().log(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AdminAppLogService().log(error, stack, severity: 'fatal');
    return true;
  };

  runApp(const ThqAdminApp());
}

class ThqAdminApp extends StatelessWidget {
  const ThqAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THQ Admin',
      debugShowCheckedModeBanner: false,
      theme: UiDesignProfile.fallback('client').theme(),
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const AdminDashboard(),
    );
  }
}
