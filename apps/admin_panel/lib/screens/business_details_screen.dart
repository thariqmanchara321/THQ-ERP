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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Business Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),

          child: Container(
            width: 900,
            padding: const EdgeInsets.all(32),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.store_outlined, size: 32),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                business.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                business.businessType ?? 'General Business',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _StatusBadge(status: business.status),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _manageLocationsDevices,
                            icon: const Icon(
                              Icons.store_mall_directory_outlined,
                            ),
                            label: const Text('Locations & Systems'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _systemHealth,
                            icon: const Icon(Icons.health_and_safety_outlined),
                            label: const Text('System Health'),
                          ),

                          OutlinedButton.icon(
                            onPressed: _customerAccounts,
                            icon: const Icon(Icons.account_balance_wallet_outlined),
                            label: const Text('Customer Accounts'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _manageDivision,
                            icon: const Icon(Icons.account_tree_outlined),
                            label: const Text('Division'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _manageSubscription,
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Subscription'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _manageInvoiceTemplates,
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Invoice Designs'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _manageRoles,
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            label: const Text('Manage Roles'),
                          ),
                          FilledButton.icon(
                            onPressed: _manageUsers,
                            icon: const Icon(Icons.manage_accounts_outlined),
                            label: const Text('Manage Users'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _archiveBusiness,
                            icon: const Icon(Icons.archive_outlined),
                            label: const Text('Archive'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            onPressed: _deleteBusiness,
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Wrap(
                    spacing: 40,
                    runSpacing: 16,
                    children: [
                      _InfoItem(label: 'Business ID', value: business.slug),

                      _InfoItem(label: 'Status', value: business.status),

                      _InfoItem(
                        label: 'Current Modules',
                        value: '${business.moduleCount}',
                      ),
                      if ((business.divisionName ?? '').isNotEmpty)
                        _InfoItem(
                          label: 'Division',
                          value:
                              '${business.divisionName} • ${business.divisionRole ?? 'child'}',
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                const Divider(),

                const SizedBox(height: 24),

                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modules',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          SizedBox(height: 5),

                          Text('Choose which features this business can use.'),
                        ],
                      ),
                    ),

                    Text(
                      '${_selectedModules.length} selected',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                FutureBuilder<List<BusinessModule>>(
                  future: _modulesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return _LoadError(
                        message: snapshot.error.toString(),
                        onRetry: _retry,
                      );
                    }

                    final modules = snapshot.data ?? [];

                    return Column(
                      children: modules.map((module) {
                        final isDashboard = module.key == 'dashboard';

                        final selected = _selectedModules.contains(module.key);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.indigo.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Colors.indigo.shade100
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: selected,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              module.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (module.description != null &&
                                    module.description!.trim().isNotEmpty)
                                  Text(module.description!),

                                const SizedBox(height: 3),

                                Text(
                                  module.category,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDashboard)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Chip(label: Text('Required')),
                                  ),

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
                                        _selectedModules.remove(module.key);
                                      }
                                    });
                                  },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 20),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      child: const Text('Cancel'),
                    ),

                    const SizedBox(width: 12),

                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
