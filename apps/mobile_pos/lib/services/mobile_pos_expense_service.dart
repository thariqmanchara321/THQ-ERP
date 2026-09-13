import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pos_session.dart';

class MobileExpenseCategory {
  final String id;
  final String name;

  const MobileExpenseCategory({required this.id, required this.name});

  factory MobileExpenseCategory.fromMap(Map<String, dynamic> map) =>
      MobileExpenseCategory(
        id: (map['category_id'] ?? map['id'])?.toString() ?? '',
        name: (map['category_name'] ?? map['name'])?.toString() ?? '',
      );
}

class MobilePosExpenseService {
  MobilePosExpenseService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<MobileExpenseCategory>> categories(PosSession session) async {
    final raw = await _client.rpc(
      'expenses_list_categories',
      params: {'p_tenant_id': session.tenantId},
    );
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => MobileExpenseCategory.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .where((row) => row.id.isNotEmpty && row.name.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> create({
    required PosSession session,
    required String categoryId,
    required DateTime expenseDate,
    required String payee,
    required String description,
    required double amount,
    required double taxAmount,
    required double roundOff,
    required String paymentMethod,
    String referenceNumber = '',
    String notes = '',
    String? requestId,
  }) async {
    final raw = await _client.rpc(
      'mobile_pos_expense_create_v601',
      params: {
        'p_tenant_id': session.tenantId,
        'p_category_id': categoryId,
        'p_expense_date': _dateOnly(expenseDate),
        'p_payee': payee.trim(),
        'p_description': description.trim(),
        'p_amount': amount,
        'p_tax_amount': taxAmount,
        'p_round_off': roundOff,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim().isEmpty
            ? null
            : referenceNumber.trim(),
        'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        'p_location_id': session.locationId,
        'p_device_id': session.deviceId,
        'p_request_id': requestId ?? const Uuid().v4(),
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected Mobile POS expense response.');
    }
    final result = Map<String, dynamic>.from(raw);
    if (result['expense_id'] == null ||
        result['journal_id'] == null ||
        result['accounting_integrity'] != 'verified') {
      throw StateError(
        'Expense response is missing verified accounting evidence.',
      );
    }
    return result;
  }

  String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
