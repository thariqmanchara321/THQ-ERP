class Business {
  final String id;
  final String name;
  final String slug;
  final String? businessType;
  final String status;
  final int moduleCount;
  final DateTime createdAt;
  final String? divisionId;
  final String? divisionName;
  final String? divisionRole;

  const Business({
    required this.id,
    required this.name,
    required this.slug,
    required this.businessType,
    required this.status,
    required this.moduleCount,
    required this.createdAt,
    this.divisionId,
    this.divisionName,
    this.divisionRole,
  });

  factory Business.fromMap(Map<String, dynamic> map) {
    final rawModuleCount = map['module_count'];

    int moduleCount = 0;

    if (rawModuleCount is int) {
      moduleCount = rawModuleCount;
    } else if (rawModuleCount is num) {
      moduleCount = rawModuleCount.toInt();
    } else if (rawModuleCount != null) {
      moduleCount = int.tryParse(rawModuleCount.toString()) ?? 0;
    }

    return Business(
      id: map['id'].toString(),
      name: map['name']?.toString() ?? '',
      slug: map['slug']?.toString() ?? '',
      businessType: map['business_type']?.toString(),
      status: map['status']?.toString() ?? '',
      moduleCount: moduleCount,
      createdAt: DateTime.parse(map['created_at'].toString()),
      divisionId: map['division_id']?.toString(),
      divisionName: map['division_name']?.toString(),
      divisionRole: map['division_role']?.toString(),
    );
  }
}
