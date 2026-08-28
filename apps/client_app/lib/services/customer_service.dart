import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';

class CustomerService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Customer>> getCustomers({required String tenantId}) async {
    final result = await _supabase.rpc(
      'customers_list_v482',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map((row) => Customer.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> createCustomer({
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
    required double creditLimit,
    required String notes,
  }) async {
    final result = await _supabase.rpc(
      'customers_create',
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
        'p_credit_limit': creditLimit,
        'p_notes': notes.trim(),
      },
    );

    return result.toString();
  }

  Future<void> updateCustomer({
    required String tenantId,
    required String customerId,
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
    required double creditLimit,
    required String notes,
    required String status,
  }) async {
    await _supabase.rpc(
      'customers_update',
      params: {
        'p_tenant_id': tenantId,
        'p_customer_id': customerId,
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
        'p_credit_limit': creditLimit,
        'p_notes': notes.trim(),
        'p_status': status,
      },
    );
  }
}
