import 'package:flutter/foundation.dart';

import '../models/client_session.dart';

/// Central location/store context for V4.2.
///
/// The public [selectedLocationId] notifier is intentionally kept stable because
/// all existing V4 screens already listen to it. V4.3 can replace the visual
/// selector without rewriting Sales/Purchases/Inventory/Accounting services.
class LocationScopeService {
  LocationScopeService._();

  static final ValueNotifier<String?> selectedLocationId =
      ValueNotifier<String?>(null);

  static void initialize(ClientSession session) {
    if (session.canViewAllLocations) {
      selectedLocationId.value = null; // All Stores is the owner/admin default.
      return;
    }
    final deviceLocation = session.device?.locationId;
    if (deviceLocation != null && session.canAccessLocation(deviceLocation)) {
      selectedLocationId.value = deviceLocation;
      return;
    }
    selectedLocationId.value = session.locations.isEmpty
        ? null
        : orderedLocations(session).first.id;
  }

  static List<ClientLocationAccess> orderedLocations(ClientSession session) {
    final rows = [...session.locations];
    int rank(ClientLocationAccess location) {
      if (location.isMain) return 0;
      if (location.isWarehouse) return 2;
      return 1;
    }

    rows.sort((a, b) {
      final roleCompare = rank(a).compareTo(rank(b));
      if (roleCompare != 0) return roleCompare;
      final orderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (orderCompare != 0) return orderCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  static ClientLocationAccess? selectedLocation(ClientSession session) {
    final id = selectedLocationId.value;
    if (id == null) return null;
    for (final location in session.locations) {
      if (location.id == id) return location;
    }
    return null;
  }

  static ClientLocationAccess? mainLocation(ClientSession session) {
    for (final location in orderedLocations(session)) {
      if (location.isMain) return location;
    }
    return session.locations.isEmpty ? null : orderedLocations(session).first;
  }

  static bool get isAllStores => selectedLocationId.value == null;

  static String scopeLabel(ClientSession session) {
    final location = selectedLocation(session);
    return location == null
        ? 'All Stores'
        : '${location.code} • ${location.name}';
  }

  static void selectAll(ClientSession session) {
    if (!session.canViewAllLocations) {
      throw StateError('This user cannot view all stores.');
    }
    selectedLocationId.value = null;
  }

  static void select(ClientSession session, String locationId) {
    if (!session.canAccessLocation(locationId)) {
      throw StateError('This user cannot access the selected store.');
    }
    selectedLocationId.value = locationId;
  }

  static String? currentForRead(ClientSession session) {
    if (session.canViewAllLocations) {
      return selectedLocationId.value;
    }
    return selectedLocationId.value ?? session.device?.locationId;
  }

  /// Returns one concrete location for any stock-changing operation.
  ///
  /// If the user is in All Stores mode, prefer the activated device location
  /// when available, then MAIN. Screens that require a different source can
  /// explicitly call [select] before posting.
  static String currentForCreate(ClientSession session) {
    final selected = selectedLocationId.value;
    if (selected != null && session.canAccessLocation(selected)) {
      return selected;
    }
    final device = session.device?.locationId;
    if (device != null && session.canAccessLocation(device)) {
      return device;
    }
    final main = mainLocation(session);
    if (main != null && session.canAccessLocation(main.id)) {
      return main.id;
    }
    if (session.locations.isNotEmpty) {
      return orderedLocations(session).first.id;
    }
    throw StateError('No accessible business location is available.');
  }

  static List<ClientLocationAccess> writableLocations(ClientSession session) {
    if (session.hasRole('owner') ||
        session.hasPermission('locations.manage_all')) {
      return orderedLocations(session);
    }
    return orderedLocations(
      session,
    ).where((location) => location.canOperate).toList();
  }
}
