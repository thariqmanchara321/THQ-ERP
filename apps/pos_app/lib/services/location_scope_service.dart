import 'package:flutter/foundation.dart';

import '../models/client_session.dart';

/// POS is intentionally bound to one activated terminal/location.
/// Even an Owner using POS should not silently post to another branch.
class LocationScopeService {
  LocationScopeService._();

  static final ValueNotifier<String?> selectedLocationId =
      ValueNotifier<String?>(null);

  static void initialize(ClientSession session) {
    selectedLocationId.value =
        session.device?.locationId ??
        (session.locations.isEmpty ? null : session.locations.first.id);
  }

  static String? current(ClientSession session) =>
      selectedLocationId.value ?? session.device?.locationId;

  /// Compatibility surface shared with Client services while preserving the
  /// POS rule that reads remain tied to the activated terminal location.
  static String? currentForRead(ClientSession session) => current(session);

  /// Stock/financial mutations from POS must always resolve to one concrete
  /// activated/access-allowed location.
  static String currentForCreate(ClientSession session) {
    final locationId = current(session);
    if (locationId == null || locationId.isEmpty) {
      throw StateError('This POS is not bound to a business location.');
    }
    if (!session.canAccessLocation(locationId)) {
      throw StateError('This POS cannot access its configured location.');
    }
    return locationId;
  }

  /// Bulk imports and Purchasing V2 on POS may only operate at the POS-bound
  /// location, never across branches.
  static List<ClientLocationAccess> writableLocations(ClientSession session) {
    final locationId = current(session);
    if (locationId == null) return const <ClientLocationAccess>[];
    return session.locations
        .where((location) => location.id == locationId && location.canOperate)
        .toList(growable: false);
  }
}
