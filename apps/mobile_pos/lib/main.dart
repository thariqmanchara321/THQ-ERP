import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/mobile_pos_entry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const ThqMobilePosApp());
}

class ThqMobilePosApp extends StatelessWidget {
  const ThqMobilePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6252D9),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF6252D9),
          secondary: const Color(0xFF8172F2),
          tertiary: const Color(0xFF2E7BEF),
          surface: Colors.white,
          onSurface: const Color(0xFF20212A),
          onSurfaceVariant: const Color(0xFF696A75),
          outline: const Color(0xFFE3E4EC),
          outlineVariant: const Color(0xFFE9EAF1),
          surfaceContainerLow: const Color(0xFFFAFAFC),
          surfaceContainer: const Color(0xFFF4F4F8),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'THQ Mobile POS',
      builder: (context, child) =>
          ThqNotificationHost(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F5F9),
        visualDensity: VisualDensity.compact,
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(fontSize: 12.5, height: 1.3),
          bodySmall: TextStyle(fontSize: 11, height: 1.25),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          labelMedium: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          labelSmall: TextStyle(fontSize: 9.8, fontWeight: FontWeight.w600),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF4F5F9),
          foregroundColor: Color(0xFF20212A),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFE5E6EE)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE2E3EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE2E3EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF6252D9), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(46, 44),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(46, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            side: const BorderSide(color: Color(0xFFE1E2EB)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(38),
            padding: const EdgeInsets.all(7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E6EE)),
          ),
        ),
      ),
      home: const MobilePosEntryScreen(),
    );
  }
}
