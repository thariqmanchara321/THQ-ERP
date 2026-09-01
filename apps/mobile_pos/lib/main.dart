import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/mobile_pos_entry_screen.dart';
Future<void> main() async {WidgetsFlutterBinding.ensureInitialized();await Supabase.initialize(url:SupabaseConfig.url,publishableKey:SupabaseConfig.publishableKey);runApp(const ThqMobilePosApp());}
class ThqMobilePosApp extends StatelessWidget{const ThqMobilePosApp({super.key});@override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'THQ Mobile POS',theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF0D47A1)).copyWith(onSurface:const Color(0xFF211F27),onSurfaceVariant:const Color(0xFF625E6A)),useMaterial3:true,inputDecorationTheme:const InputDecorationTheme(filled:true)),home:const MobilePosEntryScreen());}
