import 'package:flutter/material.dart';

import '../models/business.dart';
import '../models/business_module.dart';
import '../services/business_service.dart';
import 'business_roles_screen.dart';
import 'business_users_screen.dart';
import 'tenant_subscription_screen.dart';
import 'tenant_invoice_templates_screen.dart';
import 'business_locations_devices_screen.dart';
import 'system_health_screen.dart';
import 'customer_accounts_screen.dart';

class BusinessDetailsScreen extends StatefulWidget {
  final Business business;

  const BusinessDetailsScreen({super.key, required this.business});

  @override
  State<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends State<BusinessDetailsScreen> {
  final BusinessService _businessService = BusinessService();

  late Future<List<BusinessModule>> _modulesFuture;

  final Set<String> _selectedModules = {};

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _modulesFuture = _loadModules();
  }

  Future<List<BusinessModule>> _loadModules() async {
    final modules = await _businessService.getBusinessModules(
      tenantId: widget.business.id,
    );

    _selectedModules
      ..clear()
      ..addAll(
        modules.where((module) => module.enabled).map((module) => module.key),
      );

    _selectedModules.add('dashboard');

    return modules;
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _modulesFuture = _loadModules();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      _selectedModules.add('dashboard');

      await _businessService.updateBusinessModules(
        tenantId: widget.business.id,
        moduleKeys: _selectedModules.toList(),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _manageUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessUsersScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _manageRoles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessRolesScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _manageInvoiceTemplates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TenantInvoiceTemplatesScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _manageLocationsDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessLocationsDevicesScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _systemHealth() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SystemHealthScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _customerAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerAccountsScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _manageSubscription() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TenantSubscriptionScreen(
          tenantId: widget.business.id,
          businessName: widget.business.name,
        ),
      ),
    );
  }

  Future<void> _manageDivision() async {
    try {
      final divisions = await _businessService.getDivisions();
      if (!mounted) return;
      String? selected = widget.business.divisionId;
      String role = widget.business.divisionRole ?? 'child';
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Business Division'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Division'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Standalone / no division'),
                      ),
                      ...divisions.map(
                        (d) => DropdownMenuItem<String?>(
                          value: d['division_id']?.toString(),
                          child: Text(
                            '${d['division_name']} • ${d['division_code']}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selected = value),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 14),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'child',
                          label: Text('Child business'),
                        ),
                        ButtonSegment(
                          value: 'main',
                          label: Text('Main business'),
                        ),
                      ],
                      selected: {role},
                      onSelectionChanged: (values) =>
                          setDialogState(() => role = values.first),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (saved != true) return;
      if (selected == null) {
        await _businessService.removeBusinessFromDivision(
          tenantId: widget.business.id,
        );
      } else {
        await _businessService.assignBusinessToDivision(
          tenantId: widget.business.id,
          divisionId: selected!,
          memberType: role,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business division updated.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _archiveBusiness() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Business'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Archive ${widget.business.name}? Users and devices will be blocked, but business data is preserved.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      await _businessService.archiveBusiness(
        tenantId: widget.business.id,
        reason: reason.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _deleteBusiness() async {
    final identity = await _businessService.getBusinessIdentity(
      tenantId: widget.business.id,
    );
    if (!mounted) return;
    final businessCode = identity['business_code']?.toString() ?? '';
    final password = TextEditingController();
    final confirmation = TextEditingController();
    bool obscure = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 42,
          ),
          title: const Text('Permanently Delete Business'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes the business database records. Use Archive unless permanent deletion is truly required.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Business code: $businessCode',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmation,
                  decoration: const InputDecoration(
                    labelText: 'Type the business code',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Your Super Admin password',
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(() => obscure = !obscure),
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete Permanently'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      password.dispose();
      confirmation.dispose();
      return;
    }
    try {
      await _businessService.deleteBusiness(
        tenantId: widget.business.id,
        password: password.text,
        businessCode: confirmation.text.trim().toUpperCase(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      password.dispose();
      confirmation.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = widget.business;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          business.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.store_outlined,
                      size: 17,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          business.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${business.businessType ?? 'General Business'} | '
                          '${business.slug}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 7.8,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: business.status),
                  const SizedBox(width: 5),
                  Text(
                    '${_selectedModules.length} modules',
                    style: TextStyle(
                      fontSize: 7.8,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _manageLocationsDevices,
                    icon: const Icon(
                      Icons.store_mall_directory_outlined,
                      size: 14,
                    ),
                    label: const Text('Locations'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _systemHealth,
                    icon: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 14,
                    ),
                    label: const Text('Health'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _customerAccounts,
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 14,
                    ),
                    label: const Text('Accounts'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _manageDivision,
                    icon: const Icon(Icons.account_tree_outlined, size: 14),
                    label: const Text('Division'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _manageSubscription,
                    icon: const Icon(Icons.payments_outlined, size: 14),
                    label: const Text('Subscription'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _manageInvoiceTemplates,
                    icon: const Icon(Icons.receipt_long_outlined, size: 14),
                    label: const Text('Invoices'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _manageRoles,
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 14,
                    ),
                    label: const Text('Roles'),
                  ),
                  FilledButton.icon(
                    onPressed: _manageUsers,
                    icon: const Icon(Icons.manage_accounts_outlined, size: 14),
                    label: const Text('Users'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _archiveBusiness,
                    icon: const Icon(Icons.archive_outlined, size: 14),
                    label: const Text('Archive'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    onPressed: _deleteBusiness,
                    icon: const Icon(Icons.delete_forever_outlined, size: 14),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: _detailMetric(
                      'Business ID',
                      business.slug,
                      Icons.tag,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _detailMetric(
                      'Status',
                      business.status,
                      Icons.check_circle_outline,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _detailMetric(
                      'Modules',
                      '${business.moduleCount}',
                      Icons.extension_outlined,
                    ),
                  ),
                  if ((business.divisionName ?? '').isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Expanded(
                      child: _detailMetric(
                        'Division',
                        '${business.divisionName} | '
                            '${business.divisionRole ?? 'child'}',
                        Icons.account_tree_outlined,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .45,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'MODULE ACCESS',
                              style: TextStyle(
                                fontSize: 8.8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .3,
                              ),
                            ),
                          ),
                          Text(
                            '${_selectedModules.length} selected',
                            style: TextStyle(
                              fontSize: 7.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        color: scheme.errorContainer,
                        child: Text(
                          _error!,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 8,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    Expanded(
                      child: FutureBuilder<List<BusinessModule>>(
                        future: _modulesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return _LoadError(
                              message: snapshot.error.toString(),
                              onRetry: _retry,
                            );
                          }

                          final modules = snapshot.data ?? [];
                          return ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: modules.length,
                            itemBuilder: (context, index) {
                              final module = modules[index];
                              final isDashboard = module.key == 'dashboard';
                              final selected = _selectedModules.contains(
                                module.key,
                              );

                              return Container(
                                constraints: const BoxConstraints(
                                  minHeight: 46,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? scheme.primaryContainer.withValues(
                                          alpha: .08,
                                        )
                                      : Colors.transparent,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  value: selected,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    module.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((module.description ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        module.description!.trim(),
                                      module.category,
                                    ].join(' | '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 7.2,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  secondary: Wrap(
                                    spacing: 3,
                                    children: [
                                      if (isDashboard)
                                        const Chip(label: Text('Required')),
                                      if (module.isCore)
                                        const Chip(label: Text('Core')),
                                    ],
                                  ),
                                  onChanged: isDashboard || _saving
                                      ? null
                                      : (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedModules.add(module.key);
                                            } else {
                                              _selectedModules.remove(
                                                module.key,
                                              );
                                            }
                                          });
                                        },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 38,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 5),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 15),
                    label: Text(_saving ? 'Saving...' : 'Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailMetric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: scheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(fontSize: 7, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 5),

          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: active ? Colors.green.shade700 : Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not load modules',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(message),

          const SizedBox(height: 14),

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
