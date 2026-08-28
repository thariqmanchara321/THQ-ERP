import 'package:supabase_flutter/supabase_flutter.dart';

class BulkImportService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> importProducts({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
    String? locationId,
    String? deviceId,
  }) async {
    final result = locationId == null
        ? await _supabase.rpc(
            'inventory_bulk_create_products',
            params: {'p_tenant_id': tenantId, 'p_rows': rows},
          )
        : await _supabase.rpc(
            'inventory_bulk_create_products_v45',
            params: {
              'p_tenant_id': tenantId,
              'p_location_id': locationId,
              'p_device_id': deviceId,
              'p_rows': rows,
            },
          );

    if (result is! Map) {
      throw Exception('Unexpected product import response.');
    }

    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> importCustomers({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
  }) async {
    var success = 0;
    final errors = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final name = _text(row, 'name');
      if (name.isEmpty) {
        errors.add('Row ${i + 2}: customer name is required.');
        continue;
      }

      try {
        await _supabase.rpc(
          'customers_create',
          params: {
            'p_tenant_id': tenantId,
            'p_name': name,
            'p_contact_person': _text(row, 'contact_person'),
            'p_phone': _text(row, 'phone'),
            'p_email': _text(row, 'email'),
            'p_tax_number': _text(row, 'tax_number'),
            'p_address_line1': _text(row, 'address_line1'),
            'p_address_line2': _text(row, 'address_line2'),
            'p_city': _text(row, 'city'),
            'p_state': _text(row, 'state'),
            'p_postal_code': _text(row, 'postal_code'),
            'p_country': _text(row, 'country'),
            'p_credit_limit': _number(row, 'credit_limit'),
            'p_notes': _text(row, 'notes'),
          },
        );
        success++;
      } catch (error) {
        errors.add('Row ${i + 2} ($name): $error');
      }
    }

    return {
      'success_count': success,
      'failed_count': rows.length - success,
      'errors': errors,
    };
  }

  Future<Map<String, dynamic>> importSuppliers({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
  }) async {
    var success = 0;
    final errors = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final name = _text(row, 'name');
      if (name.isEmpty) {
        errors.add('Row ${i + 2}: supplier name is required.');
        continue;
      }

      try {
        await _supabase.rpc(
          'suppliers_create',
          params: {
            'p_tenant_id': tenantId,
            'p_name': name,
            'p_contact_person': _text(row, 'contact_person'),
            'p_phone': _text(row, 'phone'),
            'p_email': _text(row, 'email'),
            'p_tax_number': _text(row, 'tax_number'),
            'p_address_line1': _text(row, 'address_line1'),
            'p_address_line2': _text(row, 'address_line2'),
            'p_city': _text(row, 'city'),
            'p_state': _text(row, 'state'),
            'p_postal_code': _text(row, 'postal_code'),
            'p_country': _text(row, 'country'),
            'p_notes': _text(row, 'notes'),
          },
        );
        success++;
      } catch (error) {
        errors.add('Row ${i + 2} ($name): $error');
      }
    }

    return {
      'success_count': success,
      'failed_count': rows.length - success,
      'errors': errors,
    };
  }

  String _text(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  double _number(Map<String, dynamic> row, String key) =>
      double.tryParse(_text(row, key)) ?? 0.0;
}
