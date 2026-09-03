import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/admin_dashboard_v600.dart';
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
  final bool? authenticatedOverride;

  const ThqAdminApp({super.key, this.authenticatedOverride});

  @override
  Widget build(BuildContext context) {
    final authenticated =
        authenticatedOverride ??
        (Supabase.instance.client.auth.currentSession != null);

    return MaterialApp(
      title: 'THQ Admin',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          NumericZeroAutoSelect(child: child ?? const SizedBox.shrink()),
      theme: UiDesignProfile.fallback('client').theme(),
      home: authenticated ? const AdminDashboardV600() : const LoginScreen(),
    );
  }
}
