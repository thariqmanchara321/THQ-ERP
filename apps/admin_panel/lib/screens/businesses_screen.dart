import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/business.dart';
import '../services/business_service.dart';
import '../services/location_device_service.dart';
import 'business_details_screen.dart';
import 'create_business_screen.dart';

class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key});

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  final BusinessService _businessService = BusinessService();
  final LocationDeviceService _locationService = LocationDeviceService();

  late Future<List<Business>> _businessesFuture;

  @override
  void initState() {
    super.initState();

    _loadBusinesses();
  }

  void _loadBusinesses() {
    _businessesFuture = _businessService.getBusinesses();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadBusinesses();
    });

    await _businessesFuture;
  }

  Future<void> _createBusiness() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateBusinessScreen()),
    );

    if (created == true && mounted) {
      setState(() {
        _loadBusinesses();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business created successfully.')),
      );
    }
  }

  Future<void> _addChildStore() async {
    final businesses = await _businessesFuture;
    if (!mounted) return;
    if (businesses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a main business first.')),
      );
      return;
    }

    String tenantId = businesses.first.id;
    String locationType = 'branch';
    final code = TextEditingController();
    final name = TextEditingController();
    final invoicePrefix = TextEditingController();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Child Store / Location'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tenantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Main business',
                    helperText:
                        'The new store shares products, accounting and reporting with this business.',
                  ),
                  items: businesses
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(
                            '${b.name} • ${b.slug}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => tenantId = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Store code',
                          hintText: 'BR01',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Store name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: locationType,
                        decoration: const InputDecoration(
                          labelText: 'Location type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'branch',
                            child: Text('Child Branch'),
                          ),
                          DropdownMenuItem(
                            value: 'store',
                            child: Text('Store'),
                          ),
                          DropdownMenuItem(
                            value: 'warehouse',
                            child: Text('Warehouse'),
                          ),
                          DropdownMenuItem(
                            value: 'production',
                            child: Text('Production'),
                          ),
                          DropdownMenuItem(
                            value: 'office',
                            child: Text('Office'),
                          ),
                          DropdownMenuItem(
                            value: 'scrap',
                            child: Text('Scrap'),
                          ),
                          DropdownMenuItem(
                            value: 'restaurant',
                            child: Text('Restaurant'),
                          ),
                          DropdownMenuItem(
                            value: 'service_base',
                            child: Text('Service Base'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => locationType = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: invoicePrefix,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Invoice prefix',
                          hintText: 'BR01',
                        ),
                      ),
                    ),
                  ],
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add Store'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true) {
      final storeCode = code.text.trim().toUpperCase();
      final storeName = name.text.trim();
      if (storeCode.isEmpty || storeName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Store code and name are required.')),
          );
        }
      } else {
        try {
          final locations = await _locationService.locations(tenantId);
          Map<String, dynamic>? root;
          for (final row in locations) {
            if (row['hierarchy_role']?.toString() == 'main_store' ||
                row['location_code']?.toString().toUpperCase() == 'MAIN') {
              root = row;
              break;
            }
          }
          final hierarchyRole = locationType == 'warehouse'
              ? 'warehouse'
              : const ['production', 'office', 'scrap'].contains(locationType)
              ? 'operational'
              : 'child_store';
          await _locationService.saveLocation(
            tenantId: tenantId,
            parentLocationId: root?['id']?.toString(),
            code: storeCode,
            name: storeName,
            type: locationType,
            hierarchyRole: hierarchyRole,
            invoicePrefix: invoicePrefix.text.trim().isEmpty
                ? storeCode
                : invoicePrefix.text.trim().toUpperCase(),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Child store created. Open the business to activate Client/POS systems for it.',
                ),
              ),
            );
          }
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }
      }
    }
    code.dispose();
    name.dispose();
    invoicePrefix.dispose();
  }

  Future<void> _openBusiness(Business business) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BusinessDetailsScreen(business: business),
      ),
    );

    if (changed == true && mounted) {
      setState(() {
        _loadBusinesses();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business modules updated successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text(
          'Businesses',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
      ),
      body: Padding(
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
                        const Text(
                          'Business Registry',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Tenants, divisions, stores and module access',
                          style: TextStyle(
                            fontSize: 8.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                  ),
                  const SizedBox(width: 3),
                  OutlinedButton.icon(
                    onPressed: _addChildStore,
                    icon: const Icon(Icons.add_business_outlined, size: 15),
                    label: const Text('Child Store'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _createBusiness,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Create Business'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: FutureBuilder<List<Business>>(
                future: _businessesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _ErrorView(
                      message: snapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }

                  final businesses = snapshot.data ?? [];
                  if (businesses.isEmpty) {
                    return _EmptyBusinesses(onCreate: _createBusiness);
                  }

                  final activeCount = businesses
                      .where((b) => b.status.toLowerCase() == 'active')
                      .length;
                  final moduleTotal = businesses.fold<int>(
                    0,
                    (sum, b) => sum + b.moduleCount,
                  );

                  return Column(
                    children: [
                      SizedBox(
                        height: 54,
                        child: Row(
                          children: [
                            Expanded(
                              child: _adminMetric(
                                'Businesses',
                                '${businesses.length}',
                                Icons.store_outlined,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: _adminMetric(
                                'Active',
                                '$activeCount',
                                Icons.check_circle_outline,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: _adminMetric(
                                'Module Assignments',
                                '$moduleTotal',
                                Icons.extension_outlined,
                              ),
                            ),
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
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: .45),
                                child: const Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        'Business',
                                        style: TextStyle(
                                          fontSize: 8.8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Type / Division',
                                        style: TextStyle(
                                          fontSize: 8.8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Modules',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 8.8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 88,
                                      child: Text(
                                        'Status',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 8.8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 30),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: _refresh,
                                  child: ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: businesses.length,
                                    itemBuilder: (context, index) {
                                      final business = businesses[index];
                                      return _BusinessCard(
                                        business: business,
                                        onTap: () => _openBusiness(business),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminMetric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.3,
                    color: scheme.onSurfaceVariant,
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

class _BusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;

  const _BusinessCard({required this.business, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = business.status.toLowerCase() == 'active';
    final division = (business.divisionName ?? '').isEmpty
        ? 'Standalone'
        : '${business.divisionName} | ${business.divisionRole ?? 'child'}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        Icons.store_outlined,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 7),
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
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            business.slug,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 7.3,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.businessType ?? 'General Business',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8.2),
                    ),
                    Text(
                      division,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 7.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${business.moduleCount}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 8.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: Text(
                  business.status.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(
                width: 30,
                child: Icon(Icons.chevron_right, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBusinesses extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyBusinesses({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(42),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 64),
            const SizedBox(height: 20),
            const Text(
              'No businesses yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first THQ business.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Business'),
            ),
          ],
        ),
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
          const Icon(Icons.error_outline, size: 54),
          const SizedBox(height: 16),
          const Text(
            'Could not load businesses',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
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
