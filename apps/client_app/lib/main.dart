import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui/thq_brand_experience.dart';
import 'config/supabase_config.dart';
import 'screens/client_entry_screen.dart';
import 'services/app_log_service.dart';

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

  final appearance = ThqAppearanceController(appKey: 'client');
  await appearance.load();
  runApp(ThqBusinessApp(appearance: appearance));
}

class ThqBusinessApp extends StatelessWidget {
  final ThqAppearanceController? appearance;
  const ThqBusinessApp({super.key, this.appearance});

  @override
  Widget build(BuildContext context) {
    return ThqAppearanceHost(
      appKey: 'client',
      controller: appearance,
      builder: (context, mode) => MaterialApp(
        title: 'THQ Business',
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        // THQ_BRANDING_START
        builder: (context, child) => ThqMotionScope(
          child: ThqStartupGate(
            appName: 'THQ Business',
            child: ThqNotificationHost(
              child: NumericZeroAutoSelect(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        // THQ_BRANDING_END
        theme: UiDesignProfile.fallback('client').forAppearance(mode).theme(),
        home: const ClientEntryScreen(),
      ),
    );
  }
}
