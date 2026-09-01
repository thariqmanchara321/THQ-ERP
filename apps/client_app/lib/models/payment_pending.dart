class PartyPendingSummary {
  final String partyId;
  final String partyType;
  final String partyName;
  final String trackingCode;
  final String phone;
  final String email;
  final double balance;
  final double overdue;
  final double salesOutstanding;
  final double loanOutstanding;
  final double purchaseOutstanding;
  final double invoiceOutstanding;
  final double creditBalance;
  final int documentCount;
  final DateTime? nextDueDate;
  final DateTime? lastActivityDate;

  const PartyPendingSummary({
    required this.partyId,
    required this.partyType,
    required this.partyName,
    required this.trackingCode,
    required this.phone,
    required this.email,
    required this.balance,
    required this.overdue,
    required this.salesOutstanding,
    required this.loanOutstanding,
    required this.purchaseOutstanding,
    required this.invoiceOutstanding,
    required this.creditBalance,
    required this.documentCount,
    required this.nextDueDate,
    required this.lastActivityDate,
  });

  factory PartyPendingSummary.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int i(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return PartyPendingSummary(
      partyId: m['party_id']?.toString() ?? '',
      partyType: m['party_type']?.toString() ?? '',
      partyName: m['party_name']?.toString() ?? '',
      trackingCode: m['tracking_code']?.toString() ?? '',
      phone: m['phone']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      balance: n(m['balance']),
      overdue: n(m['overdue']),
      salesOutstanding: n(m['sales_outstanding']),
      loanOutstanding: n(m['loan_outstanding']),
      purchaseOutstanding: n(m['purchase_outstanding']),
      invoiceOutstanding: n(m['invoice_outstanding']),
      creditBalance: n(m['credit_balance']),
      documentCount: i(m['document_count']),
      nextDueDate: d(m['next_due_date']),
      lastActivityDate: d(m['last_activity_date']),
    );
  }
}

class PartyOpenDocument {
  final String sourceType;
  final String sourceId;
  final String reference;
  final DateTime date;
  final DateTime? dueDate;
  final double total;
  final double paid;
  final double balance;
  final String status;
  final String locationId;
  final String locationName;
  final bool overdue;
  final Map<String, dynamic> extra;

  const PartyOpenDocument({
    required this.sourceType,
    required this.sourceId,
    required this.reference,
    required this.date,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    required this.locationId,
    required this.locationName,
    required this.overdue,
    required this.extra,
  });

  factory PartyOpenDocument.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return PartyOpenDocument(
      sourceType: m['source_type']?.toString() ?? '',
      sourceId: m['source_id']?.toString() ?? '',
      reference: m['reference']?.toString() ?? '',
      date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime(2000),
      dueDate: m['due_date'] == null
          ? null
          : DateTime.tryParse(m['due_date'].toString()),
      total: n(m['total']),
      paid: n(m['paid']),
      balance: n(m['balance']),
      status: m['status']?.toString() ?? '',
      locationId: m['location_id']?.toString() ?? '',
      locationName: m['location_name']?.toString() ?? '',
      overdue: m['overdue'] == true,
      extra: m['extra'] is Map
          ? Map<String, dynamic>.from(m['extra'] as Map)
          : <String, dynamic>{},
    );
  }
}

class PartyPaymentActivity {
  final String paymentType;
  final String paymentId;
  final String reference;
  final String paymentNumber;
  final DateTime date;
  final double amount;
  final String paymentMethod;
  final String locationName;

  const PartyPaymentActivity({
    required this.paymentType,
    required this.paymentId,
    required this.reference,
    required this.paymentNumber,
    required this.date,
    required this.amount,
    required this.paymentMethod,
    required this.locationName,
  });

  factory PartyPaymentActivity.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return PartyPaymentActivity(
      paymentType: m['payment_type']?.toString() ?? '',
      paymentId: m['payment_id']?.toString() ?? '',
      reference: m['reference']?.toString() ?? '',
      paymentNumber: m['payment_number']?.toString() ?? '',
      date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime(2000),
      amount: n(m['amount']),
      paymentMethod: m['payment_method']?.toString() ?? '',
      locationName: m['location_name']?.toString() ?? '',
    );
  }
}

class PartyPaymentDetail {
  final Map<String, dynamic> party;
  final List<PartyOpenDocument> documents;
  final List<PartyPaymentActivity> recentPayments;
  final double grossOutstanding;
  final double creditBalance;
  final double netOutstanding;
  final double overdue;

  const PartyPaymentDetail({
    required this.party,
    required this.documents,
    required this.recentPayments,
    required this.grossOutstanding,
    required this.creditBalance,
    required this.netOutstanding,
    required this.overdue,
  });

  factory PartyPaymentDetail.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return PartyPaymentDetail(
      party: m['party'] is Map
          ? Map<String, dynamic>.from(m['party'] as Map)
          : <String, dynamic>{},
      documents: (m['documents'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PartyOpenDocument.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      recentPayments: (m['recent_payments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PartyPaymentActivity.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      grossOutstanding: n(m['gross_outstanding']),
      creditBalance: n(m['credit_balance']),
      netOutstanding: n(m['net_outstanding']),
      overdue: n(m['overdue']),
    );
  }
}

class PendingPaymentsData {
  final List<PartyPendingSummary> receivables;
  final List<PartyPendingSummary> payables;
  final double totalReceivable;
  final double totalPayable;

  const PendingPaymentsData({
    required this.receivables,
    required this.payables,
    required this.totalReceivable,
    required this.totalPayable,
  });

  factory PendingPaymentsData.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final totals = m['totals'] is Map
        ? Map<String, dynamic>.from(m['totals'] as Map)
        : <String, dynamic>{};
    return PendingPaymentsData(
      receivables: (m['receivables'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PartyPendingSummary.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      payables: (m['payables'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PartyPendingSummary.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      totalReceivable: n(totals['receivable']),
      totalPayable: n(totals['payable']),
    );
  }
}
