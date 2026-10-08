import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui/thq_brand_experience.dart';
import 'config/supabase_config.dart';
import 'config/thq_environment_frame.dart';
import 'screens/pos_entry_screen.dart';
import 'services/app_log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseConfig.validate();
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

  final appearance = ThqAppearanceController(appKey: 'pos');
  await appearance.load();
  runApp(ThqPosApp(appearance: appearance));
}

class ThqPosApp extends StatelessWidget {
  final ThqAppearanceController? appearance;
  const ThqPosApp({super.key, this.appearance});

  @override
  Widget build(BuildContext context) {
    return ThqAppearanceHost(
      appKey: 'pos',
      controller: appearance,
      builder: (context, mode) => MaterialApp(
        title: SupabaseConfig.appTitle('THQ POS'),
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        // THQ_BRANDING_START
        builder: (context, child) => ThqEnvironmentFrame(
          child: ThqMotionScope(
            child: ThqStartupGate(
              appName: 'THQ POS',
              child: ThqNotificationHost(
                child: NumericZeroAutoSelect(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        // THQ_BRANDING_END
        theme: UiDesignProfile.fallback('pos').forAppearance(mode).theme(),
        home: const PosEntryScreen(),
      ),
    );
  }
}
