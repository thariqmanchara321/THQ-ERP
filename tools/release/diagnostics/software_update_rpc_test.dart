import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // Allow real HTTP requests in test
  HttpOverrides.global = null;

  late SupabaseClient client;

  setUpAll(() {
    client = SupabaseClient(
      'https://yguzrxcdvyimjrfvtcvp.supabase.co',
      'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ',
    );
  });

  test('app_release_check_v820 RPC responds correctly and rejects incomplete releases', () async {
    final res = await client.rpc('app_release_check_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_channel': 'stable',
      'p_current_version': '8.1.0',
      'p_current_build': 16,
    });

    expect(res, isNotNull);
    expect(res, isA<Map>());
    final map = Map<String, dynamic>.from(res as Map);
    expect(map['app_key'], 'client');
    expect(map['platform'], 'windows');
    expect(map.containsKey('update_available'), isTrue);
    expect(map.containsKey('status'), isTrue);
    expect(map['status'], 'not_eligible');
    expect(map['update_available'], isFalse);
  });

  test('app_update_log_record_v820 successfully records telemetry without error', () async {
    final res = await client.rpc('app_update_log_record_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_from_version': '8.1.0',
      'p_from_build': 16,
      'p_to_version': '8.2.0',
      'p_to_build': 17,
      'p_status': 'checking',
      'p_details': {
        'test_runner': 'automated_rpc_verification',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    });

    expect(res, isNotNull);
    final map = Map<String, dynamic>.from(res as Map);
    expect(map['success'], isTrue);
    expect(map['log_id'], isNotNull);
  });

  test('app_release_check_v820 supports device_id targeting context and grants targeted release', () async {
    final res = await client.rpc('app_release_check_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_channel': 'stable',
      'p_current_version': '8.1.0',
      'p_current_build': 16,
      'p_device_id': 'bc8aeec1-9bce-4935-b349-168caf9a7fa4',
      'p_tenant_id': 'a659b6de-885d-44ed-9fa7-93eefa7d47d2',
    });

    expect(res, isNotNull);
    expect(res, isA<Map>());
    final map = Map<String, dynamic>.from(res as Map);
    expect(map['app_key'], 'client');
    expect(map['update_available'], isTrue);
    expect(map['status'], 'update_available');
    expect(map['latest_version'], isNotEmpty);
    expect(map['latest_build'], greaterThanOrEqualTo(17));
    expect(map['download_url'], isNotNull);
    expect(map['download_url'].toString().contains('app-release-download'), isTrue);
  });
}
