import 'dart:async';
import 'dart:io';

import 'package:client_app/services/system_health_service.dart';
import 'package:client_app/widgets/system_health_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemHealthPanel Widget Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        'thq.client.last_successful_update': '2026-10-23T10:00:00Z',
      });
    });
    testWidgets('renders all health panel metrics and compiled verification message', (tester) async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          return {'status': 'ok'};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPanel(
              healthService: service,
              autoRun: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Verify compiled update test indicator is rendered
      expect(find.text('THQ Update Test #2 — New Feature Installed'), findsOneWidget);

      // Verify header and action button
      expect(find.text('SYSTEM HEALTH & VERIFICATION'), findsOneWidget);
      expect(find.text('Run System Check'), findsOneWidget);

      // Verify metrics
      expect(find.text('Application Status'), findsOneWidget);
      expect(find.text('Running (Operational)'), findsOneWidget);
      expect(find.text('Database Connection'), findsOneWidget);
      expect(find.textContaining('Connected'), findsOneWidget);
      expect(find.text('Current Version and Build'), findsOneWidget);
      expect(find.text('v8.2.2 (Build 19)'), findsOneWidget);
      expect(find.text('Last Successful Update'), findsOneWidget);
    });

    testWidgets('displays disconnected database error message when check fails', (tester) async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          throw const SocketException('Network unreachable');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPanel(
              healthService: service,
              autoRun: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.textContaining('Network unreachable'), findsOneWidget);
    });

    testWidgets('displays timeout error when database check times out', (tester) async {
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          throw TimeoutException('Database query timed out', timeout);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPanel(
              healthService: service,
              autoRun: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.textContaining('Database query timed out'), findsOneWidget);
    });

    testWidgets('tapping Run System Check triggers check and updates UI', (tester) async {
      int checkCount = 0;
      final service = SystemHealthService(
        appVersion: '8.2.2',
        buildNumber: 19,
        customDbChecker: (timeout) async {
          checkCount++;
          return {'status': 'ok'};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPanel(
              healthService: service,
              autoRun: false, // Don't run automatically
            ),
          ),
        ),
      );

      await tester.pump();
      expect(checkCount, 0);

      // Tap Run System Check button
      final buttonFinder = find.widgetWithText(OutlinedButton, 'Run System Check');
      expect(buttonFinder, findsOneWidget);
      await tester.tap(buttonFinder);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(checkCount, 1);
      expect(find.textContaining('Connected'), findsOneWidget);
    });
  });
}
