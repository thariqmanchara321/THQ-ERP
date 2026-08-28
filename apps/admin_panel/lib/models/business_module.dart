class BusinessModule {
  final String key;
  final String name;
  final String? description;
  final String category;
  final bool isCore;
  final bool enabled;
  final int sortOrder;

  const BusinessModule({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.isCore,
    required this.enabled,
    required this.sortOrder,
  });

  factory BusinessModule.fromMap(Map<String, dynamic> map) {
    return BusinessModule(
      key: map['module_key']?.toString() ?? '',
      name: map['module_name']?.toString() ?? '',
      description: map['description']?.toString(),
      category: map['category']?.toString() ?? 'General',
      isCore: map['is_core'] == true,
      enabled: map['enabled'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
