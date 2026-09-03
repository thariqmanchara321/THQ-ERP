import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/business_role.dart';
import '../services/business_role_service.dart';

class BusinessRolesScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;

  const BusinessRolesScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });

  @override
  State<BusinessRolesScreen> createState() => _BusinessRolesScreenState();
}

class _BusinessRolesScreenState extends State<BusinessRolesScreen> {
  final BusinessRoleService _service = BusinessRoleService();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  List<BusinessRole> _roles = [];
  List<BusinessPermission> _permissions = [];

  String? _selectedRoleId;

  final Set<String> _selectedPermissions = {};

  BusinessRole? get _selectedRole {
    if (_selectedRoleId == null) {
      return null;
    }

    for (final role in _roles) {
      if (role.id == _selectedRoleId) {
        return role;
      }
    }

    return null;
  }

  bool get _ownerSelected => _selectedRole?.key == 'owner';

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _service.getRoleData(tenantId: widget.tenantId);

      if (!mounted) {
        return;
      }

      setState(() {
        _roles = data.roles;
        _permissions = data.permissions;

        if (_roles.isNotEmpty) {
          final existingSelected = _roles.any(
            (role) => role.id == _selectedRoleId,
          );

          final role = existingSelected
              ? _roles.firstWhere((role) => role.id == _selectedRoleId)
              : _roles.first;

          _selectedRoleId = role.id;

          _selectedPermissions
            ..clear()
            ..addAll(role.permissionKeys);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _selectRole(BusinessRole role) {
    if (_saving) {
      return;
    }

    setState(() {
      _selectedRoleId = role.id;

      _selectedPermissions
        ..clear()
        ..addAll(role.permissionKeys);
    });
  }

  Future<void> _save() async {
    final role = _selectedRole;

    if (role == null) {
      return;
    }

    if (role.key == 'owner') {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.updateRolePermissions(
        tenantId: widget.tenantId,
        roleId: role.id,
        permissionKeys: _selectedPermissions.toList(),
      );

      final updatedRole = BusinessRole(
        id: role.id,
        key: role.key,
        name: role.name,
        isSystem: role.isSystem,
        permissionKeys: Set<String>.from(_selectedPermissions),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final index = _roles.indexWhere((item) => item.id == role.id);

        if (index >= 0) {
          _roles[index] = updatedRole;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${role.name} permissions saved.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _selectAll() {
    if (_ownerSelected || _saving) {
      return;
    }

    setState(() {
      _selectedPermissions
        ..clear()
        ..addAll(_permissions.map((permission) => permission.key));
    });
  }

  void _clearAll() {
    if (_ownerSelected || _saving) {
      return;
    }

    setState(() {
      _selectedPermissions.clear();
    });
  }

  String _cleanError(Object error) {
    var text = error.toString();

    if (text.startsWith('Exception: ')) {
      text = text.substring(11);
    }

    return text;
  }

  Map<String, List<BusinessPermission>> _groupPermissions() {
    final groups = <String, List<BusinessPermission>>{};

    for (final permission in _permissions) {
      groups.putIfAbsent(permission.moduleName, () => []);

      groups[permission.moduleName]!.add(permission);
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text(
          'Roles & Permissions',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _roles.isEmpty
          ? _ErrorView(message: _error!, onRetry: _load)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_roles.isEmpty) {
      return const Center(child: Text('No roles found.'));
    }

    final selectedRole = _selectedRole;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_roles.length} role(s) | '
                        '${_permissions.length} permission(s)',
                        style: TextStyle(
                          fontSize: 7.8,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 235,
                  child: _RolesPanel(
                    roles: _roles,
                    selectedRoleId: _selectedRoleId,
                    onSelect: _selectRole,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: selectedRole == null
                      ? const SizedBox()
                      : _PermissionEditor(
                          role: selectedRole,
                          groupedPermissions: _groupPermissions(),
                          selectedPermissions: _selectedPermissions,
                          saving: _saving,
                          error: _error,
                          onChanged: (permissionKey, enabled) {
                            if (_ownerSelected || _saving) {
                              return;
                            }

                            setState(() {
                              if (enabled) {
                                _selectedPermissions.add(permissionKey);
                              } else {
                                _selectedPermissions.remove(permissionKey);
                              }
                            });
                          },
                          onSelectAll: _selectAll,
                          onClearAll: _clearAll,
                          onSave: _save,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RolesPanel extends StatelessWidget {
  final List<BusinessRole> roles;
  final String? selectedRoleId;

  final void Function(BusinessRole role) onSelect;

  const _RolesPanel({
    required this.roles,
    required this.selectedRoleId,
    required this.onSelect,
  });

  IconData _iconForRole(String key) {
    switch (key) {
      case 'owner':
        return Icons.workspace_premium_outlined;

      case 'manager':
        return Icons.manage_accounts_outlined;

      case 'cashier':
        return Icons.point_of_sale_outlined;

      case 'salesperson':
        return Icons.person_search_outlined;

      case 'store_keeper':
        return Icons.inventory_2_outlined;

      case 'accountant':
        return Icons.account_balance_outlined;

      default:
        return Icons.badge_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(9),
            child: Text(
              'Roles',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(5),
              itemCount: roles.length,
              itemBuilder: (context, index) {
                final role = roles[index];

                final selected = role.id == selectedRoleId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: Colors.indigo.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(_iconForRole(role.key)),
                      title: Text(role.name),
                      subtitle: Text(
                        '${role.permissionKeys.length} permissions',
                      ),
                      trailing: role.key == 'owner'
                          ? const Icon(Icons.lock_outline, size: 18)
                          : null,
                      onTap: () => onSelect(role),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionEditor extends StatelessWidget {
  final BusinessRole role;

  final Map<String, List<BusinessPermission>> groupedPermissions;

  final Set<String> selectedPermissions;

  final bool saving;
  final String? error;

  final void Function(String permissionKey, bool enabled) onChanged;

  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final Future<void> Function() onSave;

  const _PermissionEditor({
    required this.role,
    required this.groupedPermissions,
    required this.selectedPermissions,
    required this.saving,
    required this.error,
    required this.onChanged,
    required this.onSelectAll,
    required this.onClearAll,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final owner = role.key == 'owner';

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        owner
                            ? 'Owner always has full access to enabled business modules.'
                            : '${selectedPermissions.length} permissions selected',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                if (owner)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 17),
                    label: Text('Full Access'),
                  )
                else ...[
                  OutlinedButton(
                    onPressed: saving ? null : onClearAll,
                    child: const Text('Clear'),
                  ),

                  const SizedBox(width: 8),

                  OutlinedButton(
                    onPressed: saving ? null : onSelectAll,
                    child: const Text('Select All'),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          if (error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(error!, style: TextStyle(color: Colors.red.shade700)),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: groupedPermissions.entries.map((entry) {
                return _PermissionGroup(
                  moduleName: entry.key,
                  permissions: entry.value,
                  selectedPermissions: selectedPermissions,
                  locked: owner || saving,
                  onChanged: onChanged,
                );
              }).toList(),
            ),
          ),

          if (!owner) ...[
            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: saving ? null : () => onSave(),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(saving ? 'Saving...' : 'Save Permissions'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionGroup extends StatelessWidget {
  final String moduleName;

  final List<BusinessPermission> permissions;

  final Set<String> selectedPermissions;

  final bool locked;

  final void Function(String permissionKey, bool enabled) onChanged;

  const _PermissionGroup({
    required this.moduleName,
    required this.permissions,
    required this.selectedPermissions,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Text(
              moduleName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          ...permissions.map((permission) {
            final selected = selectedPermissions.contains(permission.key);

            return CheckboxListTile(
              value: selected,
              title: Text(permission.name),
              subtitle: Text(
                permission.key,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: locked
                  ? null
                  : (value) {
                      onChanged(permission.key, value == true);
                    },
            );
          }),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 58),

          const SizedBox(height: 16),

          const Text(
            'Could not load roles',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          Text(message, textAlign: TextAlign.center),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
