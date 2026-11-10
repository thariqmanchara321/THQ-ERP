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

  Future<ExpenseCategory> createCategory({
    required String tenantId,
    required String name,
    String? description,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }
    final result = await _supabase.rpc(
      'expenses_category_create',
      params: {
        'p_tenant_id': tenantId,
        'p_name': trimmedName,
        'p_description': description?.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected category creation response.');
    }
    return ExpenseCategory.fromMap(Map<String, dynamic>.from(result));
  }

  Future<ExpenseCategory> updateCategory({
    required String tenantId,
    required String categoryId,
    String? name,
    bool? active,
    String? description,
  }) async {
    final result = await _supabase.rpc(
      'expenses_category_update',
      params: {
        'p_tenant_id': tenantId,
        'p_category_id': categoryId,
        'p_name': name?.trim(),
        'p_active': active,
        'p_description': description?.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected category update response.');
    }
    return ExpenseCategory.fromMap(Map<String, dynamic>.from(result));
  }

  Future<List<ExpenseCategory>> getManageCategories({
    required String tenantId,
  }) async {
    try {
      final result = await _supabase.rpc(
        'expenses_categories_manage_list',
        params: {'p_tenant_id': tenantId},
      );
      if (result is List) {
        return result
            .map(
              (e) => ExpenseCategory.fromMap(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } catch (_) {}
    return getCategories(tenantId: tenantId);
  }

  Future<Map<String, dynamic>> getAdvancedReportDataset({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'expenses_advanced_report_dataset_v719',
        params: {
          'p_tenant_id': tenantId,
          'p_from': _date(from),
          'p_to': _date(to),
          'p_location_id':
              locationId ?? LocationScopeService.selectedLocationId.value,
        },
      );
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}

    final summary = await getExpenseSummary(
      tenantId: tenantId,
      from: from,
      to: to,
    );
    final periodDays = to.difference(from).inDays + 1;
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: periodDays - 1));
    final prevSummary = await getExpenseSummary(
      tenantId: tenantId,
      from: prevFrom,
      to: prevTo,
    );
    final expenses = await getExpenses(
      tenantId: tenantId,
      from: from,
      to: to,
    );
    return {
      'tenant_id': tenantId,
      'from': _date(from),
      'to': _date(to),
      'previous_from': _date(prevFrom),
      'previous_to': _date(prevTo),
      'location_id':
          locationId ?? LocationScopeService.selectedLocationId.value,
      'summary': summary,
      'previous_summary': prevSummary,
      'expenses': expenses
          .map(
            (e) => {
              'expense_id': e.id,
              'expense_number': e.number,
              'display_number': e.number,
              'category_id': e.categoryId,
              'category_name': e.categoryName,
              'expense_date': _date(e.expenseDate),
              'payee': e.payee,
              'description': e.description,
              'amount': e.amount,
              'tax_amount': e.taxAmount,
              'round_off': e.totalAmount - e.amount - e.taxAmount,
              'total_amount': e.totalAmount,
              'payment_method': e.paymentMethod,
              'reference_number': e.referenceNumber ?? '',
              'notes': e.notes ?? '',
              'status': e.status,
              'created_at': e.createdAt?.toIso8601String(),
            },
          )
          .toList(),
      'yard_costs': const [],
      'yard_module_enabled': false,
    };
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
