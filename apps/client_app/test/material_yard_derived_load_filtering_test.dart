import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Material Yard Derived Load Filtering & Hierarchy Tests (v723)', () {
    // Replicate authoritative logic from AggregateLoadsScreen & backend
    bool isRatePending(Map<String, dynamic> row) {
      if (row['is_rate_pending'] == true) return true;
      final invRate = row['invoice_rate'] is num
          ? (row['invoice_rate'] as num).toDouble()
          : double.tryParse(row['invoice_rate']?.toString() ?? '');
      return invRate == null || invRate <= 0;
    }

    bool isBilled(Map<String, dynamic> row) {
      if (row['workflow_status'] == 'billed') return true;
      final status = row['status']?.toString();
      if (status != 'completed') return false;

      final isInbound = row['direction'] == 'inbound';
      final hasDoc = (row[isInbound ? 'purchase_id' : 'sale_id']) != null;
      if (!hasDoc) return false;

      final invStatus = row['invoice_status']?.toString().toLowerCase();
      if (invStatus != null && invStatus.isNotEmpty) {
        return invStatus == 'posted';
      }
      final invNum = row['invoice_number']?.toString();
      return invNum != null && invNum.isNotEmpty && invStatus != 'void' && invStatus != 'cancelled';
    }

    String derivedWorkflowStatus(Map<String, dynamic> row) {
      final status = row['status']?.toString();
      if (status == 'cancelled') return 'cancelled';
      if (status == 'draft') return 'draft';
      if (isBilled(row)) return 'billed';
      if (status == 'completed' && isRatePending(row)) return 'rate_pending';
      if (status == 'completed') return 'unbilled';
      return status ?? 'draft';
    }

    bool isNeedsAction(Map<String, dynamic> row) {
      final status = row['status']?.toString();
      if (status == 'cancelled') return false;
      return !isBilled(row);
    }

    test('LOAD-20261014-000074 is confirmed and billed with purchase PUR-000021 -> Billed, NOT in Needs Action', () {
      final row = {
        'load_number': 'LOAD-20261014-000074',
        'status': 'completed',
        'direction': 'inbound',
        'purchase_id': 'f7d2f939-0123-4567-89ab-cdef01234567',
        'invoice_number': 'PUR-000021',
        'invoice_status': 'posted',
        'invoice_grand_total': 15750.00,
        'invoice_rate': 45.0,
        'quantity': 350.0,
      };

      expect(isBilled(row), isTrue);
      expect(derivedWorkflowStatus(row), equals('billed'));
      expect(isNeedsAction(row), isFalse, reason: 'Billed loads must not appear under Needs Action queue');
    });

    test('LOAD-20261015-000098 is confirmed with rate pending -> Rate Pending, included in Needs Action', () {
      final row = {
        'load_number': 'LOAD-20261015-000098',
        'status': 'completed',
        'direction': 'inbound',
        'purchase_id': null,
        'invoice_number': null,
        'invoice_rate': null,
        'is_rate_pending': true,
        'quantity': 420.0,
      };

      expect(isBilled(row), isFalse);
      expect(isRatePending(row), isTrue);
      expect(derivedWorkflowStatus(row), equals('rate_pending'));
      expect(isNeedsAction(row), isTrue, reason: 'Rate pending loads must appear in Needs Action queue');
    });

    test('Confirmed load with rate but without invoice -> Unbilled, included in Needs Action', () {
      final row = {
        'load_number': 'LOAD-20261015-000099',
        'status': 'completed',
        'direction': 'outbound',
        'sale_id': null,
        'invoice_number': null,
        'invoice_rate': 60.0,
        'quantity': 500.0,
      };

      expect(isBilled(row), isFalse);
      expect(isRatePending(row), isFalse);
      expect(derivedWorkflowStatus(row), equals('unbilled'));
      expect(isNeedsAction(row), isTrue);
    });

    test('Draft load -> Draft, included in Needs Action', () {
      final row = {
        'load_number': 'LOAD-20261016-000101',
        'status': 'draft',
        'direction': 'inbound',
        'purchase_id': null,
      };

      expect(derivedWorkflowStatus(row), equals('draft'));
      expect(isNeedsAction(row), isTrue);
    });

    test('Cancelled load -> Cancelled, excluded from Needs Action', () {
      final row = {
        'load_number': 'LOAD-20261016-000102',
        'status': 'cancelled',
        'direction': 'inbound',
      };

      expect(derivedWorkflowStatus(row), equals('cancelled'));
      expect(isNeedsAction(row), isFalse);
    });

    test('Needs Action queue acts as operational work queue by default', () {
      final allLoads = [
        {'id': 1, 'status': 'completed', 'direction': 'inbound', 'purchase_id': 'p1', 'invoice_status': 'posted'}, // Billed
        {'id': 2, 'status': 'completed', 'direction': 'inbound', 'purchase_id': null, 'invoice_rate': null, 'is_rate_pending': true}, // Rate pending
        {'id': 3, 'status': 'completed', 'direction': 'outbound', 'sale_id': null, 'invoice_rate': 50.0}, // Unbilled
        {'id': 4, 'status': 'draft', 'direction': 'inbound'}, // Draft
        {'id': 5, 'status': 'cancelled', 'direction': 'inbound'}, // Cancelled
      ];

      final needsActionLoads = allLoads.where(isNeedsAction).toList();

      expect(needsActionLoads.length, equals(3));
      expect(needsActionLoads.map((l) => l['id']), containsAll([2, 3, 4]));
      expect(needsActionLoads.map((l) => l['id']), isNot(contains(1)));
      expect(needsActionLoads.map((l) => l['id']), isNot(contains(5)));
    });
  });
}
