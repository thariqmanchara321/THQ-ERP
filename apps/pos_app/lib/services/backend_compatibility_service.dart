import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackendCompatibilityService {

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> verify() async {
    final result = await _supabase.rpc('thq_backend_contract_v47');
    if (result is! Map) {
      throw StateError('THQ backend version could not be verified.');
    }
    final contract = Map<String, dynamic>.from(result);
    final migration = (contract['migration_no'] as num?)?.toInt() ?? 0;
    final version = contract['schema_version']?.toString() ?? 'unknown';
    if (migration < ThqReleaseContract.minimumMigration ||
        version != ThqReleaseContract.appVersion) {
      throw StateError(
        'Database update required. THQ ERP 4.8.2 requires migration '
        '${ThqReleaseContract.minimumMigration} / schema ${ThqReleaseContract.appVersion}, but this backend is '
        'migration $migration / schema $version.',
      );
    }
    return contract;
  }
}
