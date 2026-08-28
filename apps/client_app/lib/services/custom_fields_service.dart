import 'package:supabase_flutter/supabase_flutter.dart';

class CustomFieldsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? entityType,
  }) async {
    final result = await _supabase.rpc(
      'custom_fields_list_v4',
      params: {'p_tenant_id': tenantId, 'p_entity_type': entityType},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> save({
    required String tenantId,
    String? id,
    required String entityType,
    required String fieldKey,
    required String label,
    required String fieldType,
    required bool requiredField,
    required bool searchable,
    required bool invoiceVisible,
    required List<String> options,
    required bool active,
    required int sortOrder,
  }) async {
    await _supabase.rpc(
      'custom_field_save_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_id': id,
        'p_entity_type': entityType,
        'p_field_key': fieldKey,
        'p_label': label,
        'p_field_type': fieldType,
        'p_required': requiredField,
        'p_searchable': searchable,
        'p_invoice_visible': invoiceVisible,
        'p_options': options,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
  }
}
