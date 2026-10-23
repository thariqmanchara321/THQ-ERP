import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  HttpOverrides.global = null;

  test('dump releases', () async {
    final client = SupabaseClient(
      'https://yguzrxcdvyimjrfvtcvp.supabase.co',
      'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ',
    );

    try {
      final releases = await client.from('platform_app_releases').select('*');
      print('=== RELEASES ===');
      for (final r in releases) {
        print('Release: id=${r['id']}, app=${r['app_key']}, platform=${r['platform']}, channel=${r['channel']}, ver=${r['version']}, build=${r['build_number']}, status=${r['status']}, target_type=${r['target_type']}, target_device_ids=${r['target_device_ids']}');
        print('  url=${r['download_url']}');
        print('  sha=${r['sha256_checksum']}');
      }
    } catch (e) {
      print('Error querying releases: $e');
    }

    try {
      final catalog = await client.rpc('platform_targeting_catalog_v820');
      print('=== CATALOG ===');
      print(catalog);
    } catch (e) {
      print('Error querying catalog (may require admin): $e');
    }

    try {
      final devices = await client.from('business_devices').select('id, device_code, name, app_type, status, last_seen_at, tenant_id, location_id');
      print('=== DEVICES ===');
      for (final d in devices) {
        print('Device: id=${d['id']}, code=${d['device_code']}, name=${d['name']}, app=${d['app_type']}, status=${d['status']}, tenant=${d['tenant_id']}');
      }
    } catch (e) {
      print('Error querying devices: $e');
    }
  });
}
