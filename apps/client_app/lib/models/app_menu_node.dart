class AppMenuNode {
  final String id;
  final String nodeKey;
  final String nodeType;
  final String? moduleKey;
  final String? parentId;
  final String label;
  final String iconKey;
  final int sortOrder;
  final bool enabled;
  final bool collapsedByDefault;
  final Map<String, dynamic> metadata;

  const AppMenuNode({
    required this.id,
    required this.nodeKey,
    required this.nodeType,
    required this.moduleKey,
    required this.parentId,
    required this.label,
    required this.iconKey,
    required this.sortOrder,
    required this.enabled,
    required this.collapsedByDefault,
    required this.metadata,
  });

  bool get isGroup => nodeType == 'group';
  bool get isModule => nodeType == 'module' && moduleKey != null;

  factory AppMenuNode.fromMap(Map<String, dynamic> map) => AppMenuNode(
    id: map['id']?.toString() ?? '',
    nodeKey: map['node_key']?.toString() ?? '',
    nodeType: map['node_type']?.toString() ?? 'module',
    moduleKey: map['module_key']?.toString(),
    parentId: map['parent_id']?.toString(),
    label: map['label']?.toString() ?? '',
    iconKey: map['icon_key']?.toString() ?? '',
    sortOrder: map['sort_order'] is num
        ? (map['sort_order'] as num).toInt()
        : int.tryParse('${map['sort_order']}') ?? 100,
    enabled: map['enabled'] != false,
    collapsedByDefault: map['collapsed_by_default'] == true,
    metadata: map['metadata'] is Map
        ? Map<String, dynamic>.from(map['metadata'] as Map)
        : <String, dynamic>{},
  );
}
