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
            if (row['location_code']?.toString().toUpperCase() == 'MAIN') {
              root = row;
              break;
            }
          }
          root ??= locations
              .where((row) => row['parent_location_id'] == null)
              .firstOrNull;
          await _locationService.saveLocation(
            tenantId: tenantId,
            parentLocationId: root?['id']?.toString(),
            code: storeCode,
            name: storeName,
            type: locationType,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Businesses',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: const [AdminHomeButton()],
      ),

      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Businesses',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text('Manage businesses using THQ.'),
                    ],
                  ),
                ),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addChildStore,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Add Child Store'),
                    ),
                    FilledButton.icon(
                      onPressed: _createBusiness,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Business'),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 30),

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

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      itemCount: businesses.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final business = businesses[index];

                        return _BusinessCard(
                          business: business,
                          onTap: () => _openBusiness(business),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
    final active = business.status.toLowerCase() == 'active';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),

        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),

          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.store_outlined),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      business.businessType ?? 'General Business',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if ((business.divisionName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${business.divisionName} • ${business.divisionRole ?? 'child'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${business.moduleCount} modules',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      business.slug,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  business.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              const Icon(Icons.chevron_right),
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
