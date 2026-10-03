import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';

class CustomerService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Customer>> getCustomers({required String tenantId}) async {
    final result = await _supabase.rpc(
      'customers_list_v621',
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
    required String gstin,
    required String gstRegistrationType,
    required String addressLine1,
    required String addressLine2,
    required String city,
    required String state,
    required String postalCode,
    required String country,
    required double creditLimit,
    required String notes,
  }) async {
    final result = await _saveCustomer(
      tenantId: tenantId,
      customerId: null,
      name: name,
      contactPerson: contactPerson,
      phone: phone,
      email: email,
      gstin: gstin,
      gstRegistrationType: gstRegistrationType,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      state: state,
      postalCode: postalCode,
      country: country,
      creditLimit: creditLimit,
      notes: notes,
      status: 'active',
    );

    final id = result['customer_id']?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('Customer save returned no customer ID.');
    }
    return id;
  }

  Future<void> updateCustomer({
    required String tenantId,
    required String customerId,
    required String name,
    required String contactPerson,
    required String phone,
    required String email,
    required String gstin,
    required String gstRegistrationType,
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
    await _saveCustomer(
      tenantId: tenantId,
      customerId: customerId,
      name: name,
      contactPerson: contactPerson,
      phone: phone,
      email: email,
      gstin: gstin,
      gstRegistrationType: gstRegistrationType,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      state: state,
      postalCode: postalCode,
      country: country,
      creditLimit: creditLimit,
      notes: notes,
      status: status,
    );
  }

  Future<Map<String, dynamic>> _saveCustomer({
    required String tenantId,
    required String? customerId,
    required String name,
    required String contactPerson,
    required String phone,
    required String email,
    required String gstin,
    required String gstRegistrationType,
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
    final result = await _supabase.rpc(
      'customer_master_save_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_customer_id': customerId,
        'p_name': name.trim(),
        'p_contact_person': contactPerson.trim(),
        'p_phone': phone.trim(),
        'p_email': email.trim(),
        'p_address_line1': addressLine1.trim(),
        'p_address_line2': addressLine2.trim(),
        'p_city': city.trim(),
        'p_state': state.trim(),
        'p_postal_code': postalCode.trim(),
        'p_country': country.trim(),
        'p_credit_limit': creditLimit,
        'p_notes': notes.trim(),
        'p_status': status,
        'p_gst_registration_type': gstRegistrationType.trim(),
        'p_gstin': gstin.trim(),
      },
    );

    if (result is! Map) {
      throw StateError('Unexpected Customer/GST save response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
