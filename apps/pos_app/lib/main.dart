import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui/thq_brand_experience.dart';
import 'config/supabase_config.dart';
import 'screens/pos_entry_screen.dart';
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
      // THQ_BRANDING_START
      builder: (context, child) => ThqMotionScope(
        child: ThqStartupGate(
          appName: 'THQ POS',
          child: ThqNotificationHost(
            child: NumericZeroAutoSelect(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      // THQ_BRANDING_END
      theme: UiDesignProfile.fallback('pos').theme(),
      home: const PosEntryScreen(),
    );
  }
}
