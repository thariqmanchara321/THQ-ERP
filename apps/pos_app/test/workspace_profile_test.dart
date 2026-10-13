import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/workspace_profile.dart';

void main() {
  group('POS ThqWorkspaceProfile - Identity and Multi-Workspace Model', () {
    test('POS Profile serialization and roundtrip integrity', () {
      final now = DateTime.now();
      final profile = ThqWorkspaceProfile(
        id: 'test-pos-profile-1',
        tenantId: 'tenant-uuid-1',
        tenantName: 'Tenzo Traders',
        businessCode: 'BIZ-4854B09A96E8',
        locationId: 'loc-uuid-1',
        locationName: 'Main Store',
        locationCode: 'MAIN',
        deviceId: 'pos-dev-uuid-1',
        deviceCode: 'POS-001',
        deviceName: 'Checkout 1',
        deviceSecret: 'pos-secret-1',
        appKey: 'pos',
        activatedAt: now,
        lastActiveAt: now,
      );

      expect(profile.displayName, equals('Tenzo Traders • Main Store'));

      final map = profile.toMap();
      final restored = ThqWorkspaceProfile.fromMap(map);

      expect(restored.id, equals(profile.id));
      expect(restored.tenantId, equals(profile.tenantId));
      expect(restored.tenantName, equals(profile.tenantName));
      expect(restored.businessCode, equals(profile.businessCode));
      expect(restored.locationId, equals(profile.locationId));
      expect(restored.locationName, equals(profile.locationName));
      expect(restored.locationCode, equals(profile.locationCode));
      expect(restored.deviceId, equals(profile.deviceId));
      expect(restored.deviceCode, equals(profile.deviceCode));
      expect(restored.deviceName, equals(profile.deviceName));
      expect(restored.deviceSecret, equals(profile.deviceSecret));
      expect(restored.appKey, equals(profile.appKey));
    });

    test('Store update without changing installation or tenant activation in POS', () {
      final now = DateTime.now();
      final profile = ThqWorkspaceProfile(
        id: 'test-pos-profile-1',
        tenantId: 'tenant-uuid-1',
        tenantName: 'Tenzo Traders',
        businessCode: 'BIZ-4854B09A96E8',
        locationId: 'loc-uuid-1',
        locationName: 'Main Store',
        locationCode: 'MAIN',
        deviceId: 'pos-dev-uuid-1',
        deviceCode: 'POS-001',
        deviceName: 'Checkout 1',
        deviceSecret: 'pos-secret-1',
        appKey: 'pos',
        activatedAt: now,
        lastActiveAt: now,
      );

      final switched = profile.copyWith(
        locationId: 'loc-uuid-2',
        locationName: 'Yard 2',
        locationCode: 'YARD2',
      );

      expect(switched.id, equals(profile.id));
      expect(switched.tenantId, equals('tenant-uuid-1'));
      expect(switched.deviceId, equals('pos-dev-uuid-1'));
      expect(switched.deviceSecret, equals('pos-secret-1'));
      expect(switched.locationId, equals('loc-uuid-2'));
      expect(switched.locationName, equals('Yard 2'));
      expect(switched.locationCode, equals('YARD2'));
      expect(switched.displayName, equals('Tenzo Traders • Yard 2'));
    });
  });
}
