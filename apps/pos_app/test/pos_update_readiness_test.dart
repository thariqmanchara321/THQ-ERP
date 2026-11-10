import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('POS Update Safety & Readiness Tests', () {
    late ErpUpdateReadinessService readiness;

    setUp(() {
      readiness = ErpUpdateReadinessService();
      readiness.reset();
    });

    test('Zero unsynced transactions and no active operations allows update', () {
      readiness.setUnsyncedQueueCount(0);
      expect(readiness.isSafeToUpdate, isTrue);
      expect(readiness.summaryBlockReason, isEmpty);
    });

    test('Pending unsynced transactions strictly blocks update with clear reason', () {
      readiness.setUnsyncedQueueCount(5);
      expect(readiness.isSafeToUpdate, isFalse);
      expect(readiness.summaryBlockReason, contains('5 unsynced offline transactions in queue'));
    });

    test('In-flight financial sale posting blocks update until completed', () {
      final token = readiness.beginOperation('pos_sale_posting', 'Posting counter cash invoice #104');
      expect(readiness.isSafeToUpdate, isFalse);
      expect(readiness.summaryBlockReason, contains('Posting counter cash invoice #104'));

      readiness.endOperation(token);
      expect(readiness.isSafeToUpdate, isTrue);
    });

    test('Multiple blockers are aggregated into summary description', () {
      readiness.setUnsyncedQueueCount(2);
      final token = readiness.beginOperation('printing', 'Printing thermal receipt');

      expect(readiness.isSafeToUpdate, isFalse);
      final reason = readiness.summaryBlockReason;
      expect(reason, contains('2 unsynced offline transactions in queue'));
      expect(reason, contains('Printing thermal receipt'));

      readiness.endOperation(token);
      expect(readiness.isSafeToUpdate, isFalse);

      readiness.setUnsyncedQueueCount(0);
      expect(readiness.isSafeToUpdate, isTrue);
    });
  });
}
