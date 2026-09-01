import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/mobile_entry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  runApp(const ThqClientMobileApp());
}
class ThqClientMobileApp extends StatelessWidget { const ThqClientMobileApp({super.key}); @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'THQ Client Mobile',theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF1B5E20)).copyWith(onSurface:const Color(0xFF211F27),onSurfaceVariant:const Color(0xFF625E6A)),useMaterial3:true,inputDecorationTheme:const InputDecorationTheme(filled:true)),home:const MobileEntryScreen()); }
