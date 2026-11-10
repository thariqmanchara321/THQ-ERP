import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Query telemetry logs for test device', () async {
    const supabaseUrl = 'https://yguzrxcdvyimjrfvtcvp.supabase.co';
    const supabaseAnonKey = 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ';

    final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final logs = await client
        .from('platform_app_update_logs')
        .select('*')
        .order('created_at', ascending: false)
        .limit(10);

    print('=== RECENT 10 UPDATE LOGS ===');
    for (final log in logs) {
      print(jsonEncode(log));
    }
  });
}
