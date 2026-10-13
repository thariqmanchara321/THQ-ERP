import 'package:client_app/models/workspace_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThqWorkspaceProfile - Identity and Multi-Workspace Model', () {
    test('Profile serialization and roundtrip integrity', () {
      final now = DateTime.now();
      final profile = ThqWorkspaceProfile(
        id: 'test-profile-1',
        tenantId: 'tenant-uuid-1',
        tenantName: 'Tenzo Traders',
        businessCode: 'BIZ-4854B09A96E8',
        locationId: 'loc-uuid-1',
        locationName: 'Main Store',
        locationCode: 'MAIN',
        deviceId: 'dev-uuid-1',
        deviceCode: 'CLIENT-001',
        deviceName: 'Counter 1',
        deviceSecret: 'secret-hash-1',
        appKey: 'client',
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

    test('Store update without changing installation or tenant activation', () {
      final now = DateTime.now();
      final profile = ThqWorkspaceProfile(
        id: 'test-profile-1',
        tenantId: 'tenant-uuid-1',
        tenantName: 'Tenzo Traders',
        businessCode: 'BIZ-4854B09A96E8',
        locationId: 'loc-uuid-1',
        locationName: 'Main Store',
        locationCode: 'MAIN',
        deviceId: 'dev-uuid-1',
        deviceCode: 'CLIENT-001',
        deviceName: 'Counter 1',
        deviceSecret: 'secret-hash-1',
        appKey: 'client',
        activatedAt: now,
        lastActiveAt: now,
      );

      final switched = profile.copyWith(
        locationId: 'loc-uuid-2',
        locationName: 'Yard 2',
        locationCode: 'YARD2',
      );

      // Installation identity and secrets remain intact
      expect(switched.id, equals(profile.id));
      expect(switched.tenantId, equals('tenant-uuid-1'));
      expect(switched.deviceId, equals('dev-uuid-1'));
      expect(switched.deviceSecret, equals('secret-hash-1'));

      // New target store is reflected
      expect(switched.locationId, equals('loc-uuid-2'));
      expect(switched.locationName, equals('Yard 2'));
      expect(switched.locationCode, equals('YARD2'));
      expect(switched.displayName, equals('Tenzo Traders • Yard 2'));
    });
  });
}
