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
}
