import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  HttpOverrides.global = null;

  test('check pg extensions via rpc or test', () async {
    final client = SupabaseClient(
      'https://yguzrxcdvyimjrfvtcvp.supabase.co',
      'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ',
    );

    // Let's test calling an RPC or check what's installed
    try {
      final res = await client.rpc('thq_backend_contract_v47');
      print('Contract: $res');
    } catch (e) {
      print('Contract error: $e');
    }
  });
}
