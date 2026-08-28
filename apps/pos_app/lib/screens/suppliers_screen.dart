import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/supplier.dart';
import '../services/supplier_service.dart';
import 'party_statement_screen.dart';

class SuppliersScreen extends StatefulWidget {
  final ClientSession session;

  const SuppliersScreen({super.key, required this.session});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final SupplierService _service = SupplierService();

  final TextEditingController _searchController = TextEditingController();

  late Future<List<Supplier>> _suppliersFuture;

  String _search = '';

  bool get _canManage => widget.session.hasPermission('suppliers.manage');

  @override
  void initState() {
    super.initState();

    _loadSuppliers();
  }

  void _loadSuppliers() {
    _suppliersFuture = _service.getSuppliers(
      tenantId: widget.session.business.id,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loadSuppliers();
    });

    await _suppliersFuture;
  }

  List<Supplier> _filter(List<Supplier> suppliers) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return suppliers;
    }

    return suppliers.where((supplier) {
      final searchable = [
        supplier.name,
        supplier.publicId,
        supplier.contactPerson ?? '',
        supplier.phone ?? '',
        supplier.email ?? '',
        supplier.taxNumber ?? '',
        supplier.city ?? '',
        supplier.state ?? '',
      ];

      return searchable.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _addSupplier() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SupplierFormDialog(session: widget.session),
    );

    if (changed == true && mounted) {
      setState(() {
        _loadSuppliers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier created successfully.')),
      );
    }
  }

  Future<void> _editSupplier(Supplier supplier) async {
    if (!_canManage) {
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SupplierFormDialog(session: widget.session, supplier: supplier),
    );

    if (changed == true && mounted) {
      setState(() {
        _loadSuppliers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier updated successfully.')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _openStatement(Supplier supplier) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartyStatementScreen(
          session: widget.session,
          partyId: supplier.id,
          customer: false,
          title: 'Supplier Statement',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suppliers',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text('Manage vendors and purchase suppliers'),
                  ],
                ),
              ),

              if (_canManage)
                FilledButton.icon(
                  onPressed: _addSupplier,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Supplier'),
                ),
            ],
          ),

          const SizedBox(height: 24),

          TextField(
            controller: _searchController,

            onChanged: (value) {
              setState(() {
                _search = value;
              });
            },

            decoration: InputDecoration(
              hintText: 'Search supplier, phone, GSTIN, city...',
              prefixIcon: const Icon(Icons.search),

              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();

                        setState(() {
                          _search = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),

              filled: true,
              fillColor: Colors.white,

              border: const OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: FutureBuilder<List<Supplier>>(
              future: _suppliersFuture,

              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _SupplierErrorView(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }

                final all = snapshot.data ?? [];

                final suppliers = _filter(all);

                if (all.isEmpty) {
                  return _EmptySuppliers(
                    canManage: _canManage,
                    onAdd: _addSupplier,
                  );
                }

                if (suppliers.isEmpty) {
                  return const Center(
                    child: Text('No suppliers match your search.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,

                  child: ListView.separated(
                    itemCount: suppliers.length,

                    separatorBuilder: (_, _) => const SizedBox(height: 10),

                    itemBuilder: (context, index) {
                      final supplier = suppliers[index];

                      return _SupplierCard(
                        supplier: supplier,

                        canManage: _canManage,

                        onEdit: () => _editSupplier(supplier),
                        onStatement: () => _openStatement(supplier),
                      );
                    },
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

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onStatement;

  const _SupplierCard({
    required this.supplier,
    required this.canManage,
    required this.onEdit,
    required this.onStatement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,

            decoration: BoxDecoration(
              color: Colors.indigo.shade50,

              borderRadius: BorderRadius.circular(13),
            ),

            child: const Icon(Icons.local_shipping_outlined),
          ),

          const SizedBox(width: 16),

          Expanded(
            flex: 3,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  supplier.name,

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 3),
                if (supplier.publicId.isNotEmpty)
                  Text(
                    'Supplier ID: ${supplier.publicId}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade600,
                    ),
                  ),
                const SizedBox(height: 3),

                Text(
                  supplier.contactPerson ?? 'No contact person',

                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 2,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  supplier.phone ?? 'No phone',

                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),

                if (supplier.email != null)
                  Text(
                    supplier.email!,

                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),

          Expanded(
            flex: 2,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  supplier.taxNumber ?? 'No Tax ID',

                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),

                Text(
                  [supplier.city, supplier.state]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(', '),

                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

            decoration: BoxDecoration(
              color: supplier.isActive
                  ? Colors.green.shade50
                  : Colors.grey.shade100,

              borderRadius: BorderRadius.circular(20),
            ),

            child: Text(
              supplier.status.toUpperCase(),

              style: TextStyle(
                fontSize: 11,

                fontWeight: FontWeight.bold,

                color: supplier.isActive
                    ? Colors.green.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ),

          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Supplier Statement',
            onPressed: onStatement,
            icon: const Icon(Icons.receipt_long_outlined),
          ),

          if (canManage) ...[
            const SizedBox(width: 12),

            IconButton(
              tooltip: 'Edit Supplier',

              onPressed: onEdit,

              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierFormDialog extends StatefulWidget {
  final ClientSession session;
  final Supplier? supplier;

  const _SupplierFormDialog({required this.session, this.supplier});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final SupplierService _service = SupplierService();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  late final TextEditingController _contactController;

  late final TextEditingController _phoneController;

  late final TextEditingController _emailController;

  late final TextEditingController _taxController;

  late final TextEditingController _address1Controller;

  late final TextEditingController _address2Controller;

  late final TextEditingController _cityController;

  late final TextEditingController _stateController;

  late final TextEditingController _postalController;

  late final TextEditingController _countryController;

  late final TextEditingController _notesController;

  String _status = 'active';

  bool _saving = false;

  String? _error;

  bool get _editing => widget.supplier != null;

  @override
  void initState() {
    super.initState();

    final supplier = widget.supplier;

    _nameController = TextEditingController(text: supplier?.name ?? '');

    _contactController = TextEditingController(
      text: supplier?.contactPerson ?? '',
    );

    _phoneController = TextEditingController(text: supplier?.phone ?? '');

    _emailController = TextEditingController(text: supplier?.email ?? '');

    _taxController = TextEditingController(text: supplier?.taxNumber ?? '');

    _address1Controller = TextEditingController(
      text: supplier?.addressLine1 ?? '',
    );

    _address2Controller = TextEditingController(
      text: supplier?.addressLine2 ?? '',
    );

    _cityController = TextEditingController(text: supplier?.city ?? '');

    _stateController = TextEditingController(text: supplier?.state ?? 'Kerala');

    _postalController = TextEditingController(text: supplier?.postalCode ?? '');

    _countryController = TextEditingController(
      text: supplier?.country ?? 'India',
    );

    _notesController = TextEditingController(text: supplier?.notes ?? '');

    _status = supplier?.status ?? 'active';
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Supplier name is required.';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_editing) {
        await _service.updateSupplier(
          tenantId: widget.session.business.id,

          supplierId: widget.supplier!.id,

          name: _nameController.text,

          contactPerson: _contactController.text,

          phone: _phoneController.text,

          email: _emailController.text,

          taxNumber: _taxController.text,

          addressLine1: _address1Controller.text,

          addressLine2: _address2Controller.text,

          city: _cityController.text,

          state: _stateController.text,

          postalCode: _postalController.text,

          country: _countryController.text,

          notes: _notesController.text,

          status: _status,
        );
      } else {
        await _service.createSupplier(
          tenantId: widget.session.business.id,

          name: _nameController.text,

          contactPerson: _contactController.text,

          phone: _phoneController.text,

          email: _emailController.text,

          taxNumber: _taxController.text,

          addressLine1: _address1Controller.text,

          addressLine2: _address2Controller.text,

          city: _cityController.text,

          state: _stateController.text,

          postalCode: _postalController.text,

          country: _countryController.text,

          notes: _notesController.text,
        );
      }

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

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalController.dispose();
    _countryController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit Supplier' : 'Add Supplier'),

      content: SizedBox(
        width: 760,

        child: SingleChildScrollView(
          child: Form(
            key: _formKey,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                _twoFields(
                  TextFormField(
                    controller: _nameController,

                    enabled: !_saving,

                    autofocus: !_editing,

                    validator: _required,

                    decoration: const InputDecoration(
                      labelText: 'Supplier Name *',

                      hintText: 'ABC Auto Electricals',

                      border: OutlineInputBorder(),
                    ),
                  ),

                  TextFormField(
                    controller: _contactController,

                    enabled: !_saving,

                    decoration: const InputDecoration(
                      labelText: 'Contact Person',

                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _twoFields(
                  TextFormField(
                    controller: _phoneController,

                    enabled: !_saving,

                    keyboardType: TextInputType.phone,

                    decoration: const InputDecoration(
                      labelText: 'Phone',

                      border: OutlineInputBorder(),
                    ),
                  ),

                  TextFormField(
                    controller: _emailController,

                    enabled: !_saving,

                    keyboardType: TextInputType.emailAddress,

                    decoration: const InputDecoration(
                      labelText: 'Email',

                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _taxController,

                  enabled: !_saving,

                  textCapitalization: TextCapitalization.characters,

                  decoration: const InputDecoration(
                    labelText: 'GSTIN / Tax ID',

                    hintText: 'Optional',

                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 24),

                const Align(
                  alignment: Alignment.centerLeft,

                  child: Text(
                    'Address',

                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _address1Controller,

                  enabled: !_saving,

                  decoration: const InputDecoration(
                    labelText: 'Address Line 1',

                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _address2Controller,

                  enabled: !_saving,

                  decoration: const InputDecoration(
                    labelText: 'Address Line 2',

                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                _twoFields(
                  TextFormField(
                    controller: _cityController,

                    enabled: !_saving,

                    decoration: const InputDecoration(
                      labelText: 'City',

                      border: OutlineInputBorder(),
                    ),
                  ),

                  TextFormField(
                    controller: _stateController,

                    enabled: !_saving,

                    decoration: const InputDecoration(
                      labelText: 'State',

                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                _twoFields(
                  TextFormField(
                    controller: _postalController,

                    enabled: !_saving,

                    decoration: const InputDecoration(
                      labelText: 'Postal Code',

                      border: OutlineInputBorder(),
                    ),
                  ),

                  TextFormField(
                    controller: _countryController,

                    enabled: !_saving,

                    decoration: const InputDecoration(
                      labelText: 'Country',

                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _notesController,

                  enabled: !_saving,

                  maxLines: 3,

                  decoration: const InputDecoration(
                    labelText: 'Notes',

                    border: OutlineInputBorder(),
                  ),
                ),

                if (_editing) ...[
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _status,

                    decoration: const InputDecoration(
                      labelText: 'Status',

                      border: OutlineInputBorder(),
                    ),

                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),

                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text('Inactive'),
                      ),
                    ],

                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _status = value;
                            });
                          },
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 18),

                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(12),

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
              ],
            ),
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },

          child: const Text('Cancel'),
        ),

        FilledButton.icon(
          onPressed: _saving ? null : _save,

          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,

                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),

          label: Text(
            _saving
                ? 'Saving...'
                : _editing
                ? 'Save Changes'
                : 'Create Supplier',
          ),
        ),
      ],
    );
  }

  Widget _twoFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(child: first),

              const SizedBox(width: 14),

              Expanded(child: second),
            ],
          );
        }

        return Column(children: [first, const SizedBox(height: 14), second]);
      },
    );
  }
}

class _EmptySuppliers extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptySuppliers({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          const Icon(Icons.local_shipping_outlined, size: 70),

          const SizedBox(height: 18),

          const Text(
            'No Suppliers Yet',

            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            canManage
                ? 'Create your first supplier to start recording purchases.'
                : 'No suppliers have been created yet.',

            style: TextStyle(color: Colors.grey.shade600),
          ),

          if (canManage) ...[
            const SizedBox(height: 22),

            FilledButton.icon(
              onPressed: onAdd,

              icon: const Icon(Icons.add),

              label: const Text('Add First Supplier'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierErrorView extends StatelessWidget {
  final String message;

  final Future<void> Function() onRetry;

  const _SupplierErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          const Icon(Icons.error_outline, size: 56),

          const SizedBox(height: 16),

          const Text(
            'Could not load suppliers',

            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
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
