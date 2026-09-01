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
    final schemaVersion = contract['schema_version']?.toString() ?? 'unknown';
    final minimumAppVersion =
        (contract['minimum_app_version']?.toString() ?? '').trim();
    final apiVersion = (contract['api_version']?.toString() ?? '').trim();

    if (migration < ThqReleaseContract.minimumMigration) {
      throw StateError(
        'Database update required. THQ ERP ${ThqReleaseContract.appVersion} '
        'requires migration ${ThqReleaseContract.minimumMigration} or newer, '
        'but this backend is migration $migration / schema $schemaVersion.',
      );
    }

    // A newer additive backend/schema is valid for an older installed Client.
    // Only block the app when the backend explicitly raises its minimum
    // supported application version (a deliberate breaking change).
    if (minimumAppVersion.isNotEmpty &&
        _compareVersions(
              ThqReleaseContract.appVersion,
              minimumAppVersion,
            ) <
            0) {
      throw StateError(
        'THQ application update required. This backend requires app version '
        '$minimumAppVersion or newer; this installation is '
        '${ThqReleaseContract.appVersion}.',
      );
    }

    if (apiVersion.isNotEmpty && apiVersion != ThqReleaseContract.apiVersion) {
      throw StateError(
        'THQ API update required. This installation supports API '
        '${ThqReleaseContract.apiVersion}, but the backend reports $apiVersion.',
      );
    }

    return contract;
  }

  int _compareVersions(String left, String right) {
    final a = _versionParts(left);
    final b = _versionParts(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  List<int> _versionParts(String value) {
    final core = value.trim().split('+').first.split('-').first;
    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}
