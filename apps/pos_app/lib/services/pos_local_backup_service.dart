import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PosLocalBackupService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String?> chooseBackupFolder() =>
      getDirectoryPath(confirmButtonText: 'Use for THQ POS backups');

  Future<String> backupNow({
    required String tenantId,
    required String businessName,
    required String deviceCode,
    required String folderPath,
  }) async {
    if (folderPath.trim().isEmpty) {
      throw Exception('Choose a local backup folder first.');
    }
    final result = await _supabase.rpc(
      'business_backup_export_v4',
      params: {'p_tenant_id': tenantId},
    );
    final safeBusiness = businessName.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '_',
    );
    final safeDevice = deviceCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final directory = Directory(folderPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}THQ_${safeBusiness}_${safeDevice}_$stamp.json',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(result), flush: true);
    return file.path;
  }
}
