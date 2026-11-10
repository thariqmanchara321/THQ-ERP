import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErpUpdateReadinessService Tests', () {
    late ErpUpdateReadinessService readiness;

    setUp(() {
      readiness = ErpUpdateReadinessService();
      readiness.reset();
    });

    test('Initial state is safe to update', () {
      expect(readiness.isSafeToUpdate, isTrue);
      expect(readiness.activeOperationCount, equals(0));
      expect(readiness.unsyncedQueueCount, equals(0));
      expect(readiness.summaryBlockReason, isEmpty);
    });

    test('Active operation blocks update', () {
      final token = readiness.beginOperation(
        'sale_posting',
        'Posting sales invoice #1001',
      );
      expect(readiness.isSafeToUpdate, isFalse);
      expect(readiness.activeOperationCount, equals(1));
      expect(
        readiness.summaryBlockReason,
        contains('Posting sales invoice #1001'),
      );

      readiness.endOperation(token);
      expect(readiness.isSafeToUpdate, isTrue);
      expect(readiness.activeOperationCount, equals(0));
    });

    test('Unsynced offline records block update', () {
      readiness.setUnsyncedQueueCount(3);
      expect(readiness.isSafeToUpdate, isFalse);
      expect(
        readiness.summaryBlockReason,
        contains('3 unsynced offline transactions'),
      );

      readiness.setUnsyncedQueueCount(0);
      expect(readiness.isSafeToUpdate, isTrue);
    });

    test('runWithProtection wraps lifecycle safely', () async {
      expect(readiness.isSafeToUpdate, isTrue);

      final result = await readiness.runWithProtection(
        key: 'purchase_posting',
        description: 'Posting purchase invoice',
        operation: () async {
          expect(readiness.isSafeToUpdate, isFalse);
          return 42;
        },
      );

      expect(result, equals(42));
      expect(readiness.isSafeToUpdate, isTrue);
    });

    test('runWithProtection cleans up even if exception is thrown', () async {
      expect(readiness.isSafeToUpdate, isTrue);

      try {
        await readiness.runWithProtection(
          key: 'failed_posting',
          description: 'Failing operation',
          operation: () async {
            expect(readiness.isSafeToUpdate, isFalse);
            throw Exception('Operation failed');
          },
        );
      } catch (_) {}

      expect(readiness.isSafeToUpdate, isTrue);
    });

    test('Schedule install on close flag', () {
      expect(readiness.isInstallOnCloseScheduled, isFalse);
      readiness.scheduleInstallOnClose(true);
      expect(readiness.isInstallOnCloseScheduled, isTrue);
    });
  });
}
