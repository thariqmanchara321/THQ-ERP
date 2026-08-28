class Supplier {
  final String id;
  final String name;
  final String publicId;

  final String? contactPerson;
  final String? phone;
  final String? email;

  final String? taxNumber;

  final String? addressLine1;
  final String? addressLine2;

  final String? city;
  final String? state;
  final String? postalCode;
  final String country;

  final String? notes;

  final String status;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Supplier({
    required this.id,
    required this.name,
    required this.publicId,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.taxNumber,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: (map['supplier_id'] ?? map['id'])?.toString() ?? '',
      name: (map['supplier_name'] ?? map['name'])?.toString() ?? '',
      publicId: (map['public_id'] ?? map['tracking_code'])?.toString() ?? '',
      contactPerson: map['contact_person']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      taxNumber: map['tax_number']?.toString(),
      addressLine1: map['address_line1']?.toString(),
      addressLine2: map['address_line2']?.toString(),
      city: map['city']?.toString(),
      state: map['state']?.toString(),
      postalCode: map['postal_code']?.toString(),
      country: map['country']?.toString() ?? 'India',
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }

  bool get isActive => status == 'active';
}
