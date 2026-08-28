class ErpModule {
  final String key;
  final String name;
  final String? description;
  final String category;
  final bool isCore;
  final int sortOrder;

  const ErpModule({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.isCore,
    required this.sortOrder,
  });

  factory ErpModule.fromMap(Map<String, dynamic> map) {
    return ErpModule(
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      category: map['category']?.toString() ?? 'General',
      isCore: map['is_core'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
