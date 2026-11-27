class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yguzrxcdvyimjrfvtcvp.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ',
  );

  static const String environment = String.fromEnvironment(
    'THQ_ENV',
    defaultValue: 'production',
  );

  static bool get isTest => environment == 'test';
}
