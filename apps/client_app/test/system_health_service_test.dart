import 'dart:async';
import 'dart:io';

import 'package:client_app/services/system_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemHealthService Unit Tests', () {
    test('reports runtime operational and correct version and build', () async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return {'status': 'ok'};
        },
      );

      final report = await service.runSystemCheck();

      expect(report.isRuntimeOperational, isTrue);
      expect(report.appVersion, '8.2.2');
      expect(report.buildNumber, 19);
      expect(report.versionBuildDisplay, 'v8.2.2 (Build 19)');
      expect(report.applicationStatusDisplay, 'Running (Operational)');
      expect(report.updateVerificationMessage, 'THQ Update Test #2 — New Feature Installed');
      expect(report.databaseStatus, DatabaseConnectionStatus.connected);
      expect(report.databaseLatencyMs, isNotNull);
      expect(report.databaseLatencyMs, greaterThanOrEqualTo(0));
    });

    test('handles database connectivity timeout gracefully', () async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          // Simulate query exceeding timeout
          throw TimeoutException('Database query timed out', timeout);
        },
      );

      final report = await service.runSystemCheck(timeout: const Duration(milliseconds: 100));

      expect(report.databaseStatus, DatabaseConnectionStatus.disconnected);
      expect(report.databaseErrorMessage, contains('timed out'));
      expect(report.databaseLatencyMs, isNull);
    });

    test('handles database connectivity network failure gracefully', () async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          throw const SocketException('Connection refused to db.supabase.co:5432');
        },
      );

      final report = await service.runSystemCheck();

      expect(report.databaseStatus, DatabaseConnectionStatus.disconnected);
      expect(report.databaseErrorMessage, contains('Connection refused'));
      expect(report.databaseLatencyMs, isNull);
    });

    test('handles uninitialized Supabase client without crashing', () async {
      // Pass null client and no custom checker
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
      );

      final report = await service.runSystemCheck();

      expect(report.databaseStatus, DatabaseConnectionStatus.disconnected);
      expect(report.databaseErrorMessage, contains('Supabase client is not initialized'));
    });
  });
}
