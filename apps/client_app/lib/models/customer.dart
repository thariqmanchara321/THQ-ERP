class Customer {
  final String id;
  final String name;
  final String publicId;

  final String? contactPerson;
  final String? phone;
  final String? email;

  final String? taxNumber;

  final bool gstConfigured;
  final String? gstProfileId;
  final String gstRegistrationType;
  final String? gstGstin;
  final String? gstStateCode;
  final String? gstPlaceOfSupplyCode;
  final String? gstValidationStatus;

  final String? addressLine1;
  final String? addressLine2;

  final String? city;
  final String? state;
  final String? postalCode;
  final String country;

  final double creditLimit;
  final String? priceListId;
  final String? priceListName;

  final String? notes;

  final bool isWalkIn;
  final String status;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Customer({
    required this.id,
    required this.name,
    required this.publicId,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.taxNumber,
    required this.gstConfigured,
    required this.gstProfileId,
    required this.gstRegistrationType,
    required this.gstGstin,
    required this.gstStateCode,
    required this.gstPlaceOfSupplyCode,
    required this.gstValidationStatus,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.creditLimit,
    required this.priceListId,
    required this.priceListName,
    required this.notes,
    required this.isWalkIn,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';

  String get gstStatusLabel {
    switch (gstRegistrationType) {
      case 'registered':
        return 'Registered';
      case 'composition':
        return 'Composition';
      case 'sez':
        return 'SEZ';
      case 'export':
        return 'Export';
      case 'exempt':
        return 'Exempt';
      case 'unregistered':
      default:
        return 'Unregistered';
    }
  }

  String get gstSummary {
    if (!gstConfigured) {
      final oldTax = taxNumber?.trim() ?? '';
      return oldTax.isEmpty ? 'GST not synced' : 'GST not synced | $oldTax';
    }
    final value = gstGstin?.trim() ?? '';
    return value.isEmpty ? gstStatusLabel : '$gstStatusLabel | $value';
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final taxNumber = map['tax_number']?.toString();
    final gstRegistrationType =
        map['gst_registration_type']?.toString() ??
        ((taxNumber ?? '').trim().isEmpty ? 'unregistered' : 'registered');

    return Customer(
      id: (map['customer_id'] ?? map['id'])?.toString() ?? '',
      name: (map['customer_name'] ?? map['name'])?.toString() ?? '',
      publicId: (map['public_id'] ?? map['tracking_code'])?.toString() ?? '',
      contactPerson: map['contact_person']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      taxNumber: taxNumber,
      gstConfigured: map['gst_configured'] == true,
      gstProfileId: map['gst_profile_id']?.toString(),
      gstRegistrationType: gstRegistrationType,
      gstGstin: (map['gst_gstin'] ?? map['tax_number'])?.toString(),
      gstStateCode: map['gst_state_code']?.toString(),
      gstPlaceOfSupplyCode: map['gst_place_of_supply_code']?.toString(),
      gstValidationStatus: map['gst_validation_status']?.toString(),
      addressLine1: map['address_line1']?.toString(),
      addressLine2: map['address_line2']?.toString(),
      city: map['city']?.toString(),
      state: map['state']?.toString(),
      postalCode: map['postal_code']?.toString(),
      country: map['country']?.toString() ?? 'India',
      creditLimit: number(map['credit_limit']),
      priceListId: map['price_list_id']?.toString(),
      priceListName: map['price_list_name']?.toString(),
      notes: map['notes']?.toString(),
      isWalkIn: map['is_walk_in'] == true,
      status: map['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}
