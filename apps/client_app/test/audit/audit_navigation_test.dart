import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_screen.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/models/client_session.dart';
import 'package:client_app/services/location_scope_service.dart';

const session = ClientSession(
  business: ClientBusiness(
    id: 'tenant',
    membershipId: 'member',
    name: 'Business',
    slug: 'business',
    businessType: null,
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {'audit_center.view'},
  currencyCode: 'INR',
  timezone: 'UTC',
  locale: 'en',
  canViewAllLocations: true,
);

class AuditFake extends AuditIntelligenceService {
  final calls = <String>[];
  final old = Completer<Map<String, dynamic>>();
  bool delay = false;
  String? finding;
  @override
  Future<Map<String, dynamic>> workspace({
    required String tenantId,
    required String view,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    String severity = '',
    String status = '',
    String sort = 'date',
    bool descending = true,
    int offset = 0,
    String sourceType = '',
  }) async {
    calls.add('$view:${locationId ?? "all"}:$query');
    if (delay && locationId == null) return old.future;
    return {
      'rows': [
        {
          'id': 'f-1',
          'finding_id': 'f-1',
          'title': locationId == null ? 'Correct finding' : 'Store finding',
          'severity': 'needs_review',
          'status': 'open',
          'entity_type': 'sale',
          'entity_id': 'sale-1',
        },
      ],
      'total_rows': 1,
      'summary': {},
      'checks': {},
    };
  }

  @override
  Future<Map<String, dynamic>> findingDetail({
    required String tenantId,
    required String findingId,
  }) async {
    finding = findingId;
    return {
      'finding': {'id': findingId, 'title': 'Finding evidence'},
      'events': [],
    };
  }
}

Widget screen(AuditFake service) => MaterialApp(
  home: Scaffold(
    body: AuditIntelligenceScreen(session: session, service: service),
  ),
);
void main() {
  setUp(() => LocationScopeService.selectedLocationId.value = null);
  testWidgets('finding row opens the backend finding ID', (tester) async {
    final service = AuditFake();
    await tester.pumpWidget(screen(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct finding'));
    await tester.pumpAndSettle();
    expect(service.finding, 'f-1');
    expect(find.text('Finding evidence'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('store change discards a late response from the old scope', (
    tester,
  ) async {
    final service = AuditFake()..delay = true;
    await tester.pumpWidget(screen(service));
    await tester.pump();
    LocationScopeService.selectedLocationId.value = 'store';
    await tester.pumpAndSettle();
    expect(find.text('Store finding'), findsOneWidget);
    service.old.complete({
      'rows': [
        {'title': 'Stale finding'},
      ],
      'total_rows': 1,
    });
    await tester.pumpAndSettle();
    expect(find.text('Stale finding'), findsNothing);
    expect(service.calls, ['findings:all:', 'findings:store:']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
