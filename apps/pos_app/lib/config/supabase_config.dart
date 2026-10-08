class SupabaseConfig {
  static const productionRef = 'yguzrxcdvyimjrfvtcvp';
  static const testRef = 'krejepenqgcmnsugbpmv';

  static const defaultProductionUrl = 'https://yguzrxcdvyimjrfvtcvp.supabase.co';
  static const defaultProductionKey = 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ';

  static const defaultTestUrl = 'https://krejepenqgcmnsugbpmv.supabase.co';
  static const defaultTestKey = 'sb_publishable_aSDI9i6gG9oP2-Bcsy0nFg_aKZDiWev';

  /// Environment: 'production' or 'test'.
  /// In this TEST workspace / staging branch, default is 'test' so development
  /// and debugging never accidentally touch the production database.
  static const environment = String.fromEnvironment('THQ_ENV', defaultValue: 'test');

  static bool get isTest => environment == 'test';
  static String appTitle(String title) => isTest ? '$title TEST' : title;

  static const String _explicitUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _explicitKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static String get url {
    if (_explicitUrl.isNotEmpty) return _explicitUrl;
    return isTest ? defaultTestUrl : defaultProductionUrl;
  }

  static String get publishableKey {
    if (_explicitKey.isNotEmpty) return _explicitKey;
    return isTest ? defaultTestKey : defaultProductionKey;
  }

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

  static const publishableProductionKey = defaultProductionKey;
}
