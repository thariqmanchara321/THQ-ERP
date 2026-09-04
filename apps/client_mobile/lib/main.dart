import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/mobile_entry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const ThqClientMobileApp());
}

class ThqClientMobileApp extends StatelessWidget {
  const ThqClientMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF6C5CE7),
          secondary: const Color(0xFF8D7CF6),
          surface: Colors.white,
          onSurface: const Color(0xFF211F27),
          onSurfaceVariant: const Color(0xFF6A6673),
          outline: const Color(0xFFE7E4F1),
          outlineVariant: const Color(0xFFEDEAF5),
          surfaceContainerLow: const Color(0xFFFAF9FD),
          surfaceContainer: const Color(0xFFF5F3FA),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'THQ Client Mobile',
      builder: (context, child) =>
          ThqNotificationHost(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        visualDensity: VisualDensity.compact,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.15,
          ),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(fontSize: 13, height: 1.35),
          bodySmall: TextStyle(fontSize: 11.5, height: 1.3),
          labelLarge: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF5F6FA),
          foregroundColor: Color(0xFF211F27),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF211F27),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE9E6F1)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE7E4F1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE7E4F1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            side: const BorderSide(color: Color(0xFFE2DFF0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 62,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFFEAE6FF),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 21,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF6C5CE7)
                  : const Color(0xFF7B7785),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 10.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF6C5CE7)
                  : const Color(0xFF7B7785),
            ),
          ),
        ),
      ),
      home: const MobileEntryScreen(),
    );
  }
}
