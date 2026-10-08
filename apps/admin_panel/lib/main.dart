import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'config/thq_environment_frame.dart';
import 'screens/admin_dashboard_v600.dart';
import 'screens/login_screen.dart';
import 'services/app_log_service.dart';
import 'ui/thq_brand_experience.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseConfig.validate();
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

  final appearance = ThqAppearanceController(appKey: 'admin');
  await appearance.load();
  runApp(ThqAdminApp(appearance: appearance));
}

class ThqAdminApp extends StatelessWidget {
  final ThqAppearanceController? appearance;
  final bool? authenticatedOverride;

  const ThqAdminApp({super.key, this.authenticatedOverride, this.appearance});

  @override
  Widget build(BuildContext context) {
    final authenticated =
        authenticatedOverride ??
        (Supabase.instance.client.auth.currentSession != null);

    return ThqAppearanceHost(
      appKey: 'admin',
      controller: appearance,
      builder: (context, mode) => MaterialApp(
        title: SupabaseConfig.appTitle('THQ Admin'),
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => ThqEnvironmentFrame(
          child: ThqMotionScope(
            child: ThqStartupGate(
              appName: 'THQ Admin',
              child: ThqNotificationHost(
                child: NumericZeroAutoSelect(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        theme: UiDesignProfile.fallback('admin').forAppearance(mode).theme(),
        home: authenticated ? const AdminDashboardV600() : const LoginScreen(),
      ),
    );
  }
}
