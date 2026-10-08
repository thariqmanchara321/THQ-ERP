import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import 'ui/thq_brand_experience.dart';
import 'config/supabase_config.dart';
import 'screens/mobile_entry_screen.dart';
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
      MobileAppLogService().log(error: details.exception, stack: details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      MobileAppLogService().log(error: error, stack: stack, severity: 'fatal'),
    );
    return true;
  };

  final appearance = ThqAppearanceController(appKey: 'client_mobile');
  await appearance.load();
  runApp(ThqClientMobileApp(appearance: appearance));
}

class ThqClientMobileApp extends StatelessWidget {
  final ThqAppearanceController? appearance;
  const ThqClientMobileApp({super.key, this.appearance});

  @override
  Widget build(BuildContext context) {
    return ThqAppearanceHost(
      appKey: 'client_mobile',
      controller: appearance,
      builder: (context, mode) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        title: 'THQ Client Mobile',
        // THQ_BRANDING_START
        builder: (context, child) => ThqMotionScope(
          child: ThqStartupGate(
            appName: 'THQ Client Mobile',
            child: ThqMobileProductionFrame(
              child: ThqNotificationHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        // THQ_BRANDING_END
        theme: ThqMobileTheme.client(appearance: mode),
        home: const MobileEntryScreen(),
      ),
    );
  }
}
