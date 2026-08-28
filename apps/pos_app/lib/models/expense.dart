class Expense {
  final String id;
  final String number;
  final String categoryId;
  final String categoryName;
  final DateTime expenseDate;
  final String payee;
  final String description;
  final double amount;
  final double taxAmount;
  final double totalAmount;
  final String paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final String status;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    required this.number,
    required this.categoryId,
    required this.categoryName,
    required this.expenseDate,
    required this.payee,
    required this.description,
    required this.amount,
    required this.taxAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.notes,
    required this.status,
    required this.createdAt,
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return Expense(
      id: map['expense_id']?.toString() ?? '',
      number: map['expense_number']?.toString() ?? '',
      categoryId: map['category_id']?.toString() ?? '',
      categoryName: map['category_name']?.toString() ?? 'Other',
      expenseDate: DateTime.parse(map['expense_date'].toString()),
      payee: map['payee']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      amount: n(map['amount']),
      taxAmount: n(map['tax_amount']),
      totalAmount: n(map['total_amount']),
      paymentMethod: map['payment_method']?.toString() ?? '',
      referenceNumber: map['reference_number']?.toString(),
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'posted',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

class ExpenseCategory {
  final String id;
  final String name;
  final bool active;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.active,
  });

  factory ExpenseCategory.fromMap(Map<String, dynamic> map) {
    return ExpenseCategory(
      id: map['category_id']?.toString() ?? map['id']?.toString() ?? '',
      name: map['category_name']?.toString() ?? map['name']?.toString() ?? '',
      active: map['active'] != false,
    );
  }
}
