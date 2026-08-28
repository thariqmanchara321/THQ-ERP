import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class BackupService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> createBackupJson({required String tenantId}) async {
    final result = await _supabase.rpc(
      'business_backup_export_v4',
      params: {'p_tenant_id': tenantId},
    );
    return const JsonEncoder.withIndent('  ').convert(result);
  }
}
