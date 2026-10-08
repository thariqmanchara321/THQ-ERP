import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/config/supabase_config.dart';

void main() {
  const testUrl = 'https://krejepenqgcmnsugbpmv.supabase.co';
  const prodUrl = 'https://yguzrxcdvyimjrfvtcvp.supabase.co';
  const key = 'sb_publishable_test_fixture';

  test('test environment accepts its assigned project', () {
    expect(() => SupabaseConfig.validateValues('test', testUrl, key), returnsNormally);
  });

  test('test environment defaults to test backend and passes validation', () {
    expect(SupabaseConfig.isTest, isTrue);
    expect(SupabaseConfig.url, SupabaseConfig.defaultTestUrl);
    expect(SupabaseConfig.publishableKey, SupabaseConfig.defaultTestKey);
    expect(() => SupabaseConfig.validate(), returnsNormally);
  });

  test('release guard rejects production access from test', () {
    expect(() => SupabaseConfig.validateValues('test', prodUrl, key), throwsStateError);
    expect(() => SupabaseConfig.validateValues('test', testUrl, SupabaseConfig.publishableProductionKey), throwsStateError);
  });

  test('production cannot point at staging', () {
    expect(() => SupabaseConfig.validateValues('production', testUrl, key), throwsStateError);
  });

  test('unknown environments and non-public keys fail closed', () {
    expect(() => SupabaseConfig.validateValues('staging', testUrl, key), throwsStateError);
    expect(() => SupabaseConfig.validateValues('test', testUrl, 'sb_secret_example'), throwsStateError);
  });

  test('host spoofing and insecure URLs are rejected', () {
    for (final url in ['http://krejepenqgcmnsugbpmv.supabase.co', '$testUrl.evil.example', '$testUrl?redirect=production', '$testUrl/rest/v1']) {
      expect(() => SupabaseConfig.validateValues('test', url, key), throwsStateError);
    }
  });
}
