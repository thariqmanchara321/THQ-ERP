import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';
import '../models/expense.dart';

class ExpenseService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Expense>> getExpenses({
    required String tenantId,
    DateTime? from,
    DateTime? to,
  }) async {
    final activation = await _activation(tenantId);
    final day = from ?? to ?? DateTime.now();
    final result = await _supabase.rpc(
      'pos_expenses_today_v473',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': activation.deviceId,
        'p_day': _date(day),
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
  }) async {
    await _supabase.rpc(
      'expenses_update_v489',
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
      },
    );
  }

  Future<DeviceActivation> _activation(String tenantId) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return activation;
  }

  Future<Map<String, dynamic>> _originParams(String tenantId) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return {
      'p_location_id': activation.locationId,
      'p_device_id': activation.deviceId,
    };
  }

  String _date(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
}
