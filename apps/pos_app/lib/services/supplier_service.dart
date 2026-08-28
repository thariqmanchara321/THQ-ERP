import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/supplier.dart';

class SupplierService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Supplier>> getSuppliers({required String tenantId}) async {
    final result = await _supabase.rpc(
      'suppliers_list_v32',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map((row) => Supplier.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> createSupplier({
    required String tenantId,
    required String name,
    required String contactPerson,
    required String phone,
    required String email,
    required String taxNumber,
    required String addressLine1,
    required String addressLine2,
    required String city,
    required String state,
    required String postalCode,
    required String country,
    required String notes,
  }) async {
    final result = await _supabase.rpc(
      'suppliers_create',
      params: {
        'p_tenant_id': tenantId,
        'p_name': name.trim(),
        'p_contact_person': contactPerson.trim(),
        'p_phone': phone.trim(),
        'p_email': email.trim(),
        'p_tax_number': taxNumber.trim(),
        'p_address_line1': addressLine1.trim(),
        'p_address_line2': addressLine2.trim(),
        'p_city': city.trim(),
        'p_state': state.trim(),
        'p_postal_code': postalCode.trim(),
        'p_country': country.trim(),
        'p_notes': notes.trim(),
      },
    );

    return result.toString();
  }

  Future<void> updateSupplier({
    required String tenantId,
    required String supplierId,
    required String name,
    required String contactPerson,
    required String phone,
    required String email,
    required String taxNumber,
    required String addressLine1,
    required String addressLine2,
    required String city,
    required String state,
    required String postalCode,
    required String country,
    required String notes,
    required String status,
  }) async {
    await _supabase.rpc(
      'suppliers_update',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': supplierId,
        'p_name': name.trim(),
        'p_contact_person': contactPerson.trim(),
        'p_phone': phone.trim(),
        'p_email': email.trim(),
        'p_tax_number': taxNumber.trim(),
        'p_address_line1': addressLine1.trim(),
        'p_address_line2': addressLine2.trim(),
        'p_city': city.trim(),
        'p_state': state.trim(),
        'p_postal_code': postalCode.trim(),
        'p_country': country.trim(),
        'p_notes': notes.trim(),
        'p_status': status,
      },
    );
  }
}
