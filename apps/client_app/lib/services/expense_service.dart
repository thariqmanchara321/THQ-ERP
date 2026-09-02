import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';
import 'location_scope_service.dart';
import '../models/expense.dart';

class ExpenseService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Expense>> getExpenses({
    required String tenantId,
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await _supabase.rpc(
      'expenses_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
        'p_from_date': from == null ? null : _date(from),
        'p_to_date': to == null ? null : _date(to),
      },
    );
    return (result as List)
        .map((e) => Expense.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ExpenseCategory>> getCategories({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'expenses_list_categories',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List)
        .map(
          (e) => ExpenseCategory.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> createExpense({
    required String tenantId,
    required String categoryId,
    required DateTime expenseDate,
    required String payee,
    required String description,
    required double amount,
    required double taxAmount,
    double roundOff = 0,
    required String paymentMethod,
    required String referenceNumber,
    required String notes,
  }) async {
    final result = await _supabase.rpc(
      'expenses_create_v489',
      params: {
        'p_tenant_id': tenantId,
        'p_category_id': categoryId,
        'p_expense_date': _date(expenseDate),
        'p_payee': payee.trim(),
        'p_description': description.trim(),
        'p_amount': amount,
        'p_tax_amount': taxAmount,
        'p_round_off': roundOff,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        ...await _originParams(tenantId),
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is! Map) throw Exception('Unexpected expense response.');
    return Map<String, dynamic>.from(result);
  }

  Future<void> updateExpense({
    required String tenantId,
    required String expenseId,
    required String categoryId,
    required DateTime expenseDate,
    required String payee,
    required String description,
    required double amount,
    required double taxAmount,
    double roundOff = 0,
    required String paymentMethod,
    required String referenceNumber,
    required String notes,
    required String reason,
  }) async {
    await _supabase.rpc(
      'expenses_update_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_expense_id': expenseId,
        'p_category_id': categoryId,
        'p_expense_date': _date(expenseDate),
        'p_payee': payee.trim(),
        'p_description': description.trim(),
        'p_amount': amount,
        'p_tax_amount': taxAmount,
        'p_round_off': roundOff,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> getExpenseDetail({
    required String tenantId,
    required String expenseId,
  }) async {
    final raw = await _supabase.rpc(
      'expense_detail_v600',
      params: {'p_tenant_id': tenantId, 'p_expense_id': expenseId},
    );
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw StateError('Unexpected expense detail response.');
  }

  Future<Map<String, dynamic>> getExpenseSummary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final raw = await _supabase.rpc(
      'expense_summary_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _originParams(String tenantId) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return {
      'p_location_id':
          LocationScopeService.selectedLocationId.value ??
          activation.locationId,
      'p_device_id': activation.deviceId,
    };
  }

  String _date(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
}
