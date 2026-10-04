class SupabaseConfig {
  static const productionRef = 'yguzrxcdvyimjrfvtcvp';
  static const testRef = 'krejepenqgcmnsugbpmv';
  static const environment = String.fromEnvironment('THQ_ENV', defaultValue: 'production');
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://yguzrxcdvyimjrfvtcvp.supabase.co');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ');

  static bool get isTest => environment == 'test';
  static String appTitle(String title) => isTest ? '$title TEST' : title;

  // Runs before initialization, logging, sessions or offline synchronization.
  // Do not use assert: these guards must also run in release builds.
  static void validate() {
    validateValues(environment, url, publishableKey);
  }

  static void validateValues(String env, String apiUrl, String key) {
    if (env != 'production' && env != 'test') {
      throw StateError('THQ_ENV must be production or test.');
    }
    final expectedRef = env == 'test' ? testRef : productionRef;
    final uri = Uri.tryParse(apiUrl);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != '$expectedRef.supabase.co' || uri.userInfo.isNotEmpty ||
        uri.hasPort || (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery || uri.hasFragment) {
      throw StateError('THQ $env must use its assigned Supabase project.');
    }
    if (!key.startsWith('sb_publishable_') || key.trim() != key) {
      throw StateError('A publishable Supabase client key is required.');
    }
    if (env == 'test' && key == publishableProductionKey) {
      throw StateError('TEST cannot use the production publishable key.');
    }
  }

  static const publishableProductionKey = 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ';
}
