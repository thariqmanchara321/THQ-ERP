import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';
import 'party_statement_screen.dart';

class CustomersScreen extends StatefulWidget {
  final ClientSession session;

  const CustomersScreen({super.key, required this.session});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final CustomerService _service = CustomerService();

  final TextEditingController _searchController = TextEditingController();

  late Future<List<Customer>> _customersFuture;

  String _search = '';

  bool get _canManage => widget.session.hasPermission('customers.manage');

  @override
  void initState() {
    super.initState();

    _loadCustomers();
  }

  void _loadCustomers() {
    _customersFuture = _service.getCustomers(
      tenantId: widget.session.business.id,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loadCustomers();
    });

    await _customersFuture;
  }

  List<Customer> _filter(List<Customer> customers) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      final values = [
        customer.name,
        customer.publicId,
        customer.contactPerson ?? '',
        customer.phone ?? '',
        customer.email ?? '',
        customer.taxNumber ?? '',
        customer.city ?? '',
        customer.state ?? '',
      ];

      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _addCustomer() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerFormDialog(session: widget.session),
    );

    if (changed == true && mounted) {
      setState(() {
        _loadCustomers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer created successfully.')),
      );
    }
  }

  Future<void> _editCustomer(Customer customer) async {
    if (!_canManage || customer.isWalkIn) {
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CustomerFormDialog(session: widget.session, customer: customer),
    );

    if (changed == true && mounted) {
      setState(() {
        _loadCustomers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer updated successfully.')),
      );
    }
  }

  Future<void> _openStatement(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartyStatementScreen(
          session: widget.session,
          partyId: customer.id,
          customer: true,
          title: 'Customer Statement',
        ),
      ),
    );
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      const Text(
                        'Customers',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Customer master and statements',
                        style: TextStyle(
                          fontSize: 9.8,
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
                if (_canManage) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: _addCustomer,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Add Customer'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search ID, name, phone, GSTIN, city...',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                        icon: const Icon(Icons.close, size: 15),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _customersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 15),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final customers = _filter(snapshot.data ?? []);
                if (customers.isEmpty) {
                  return const Center(child: Text('No customers found.'));
                }

                return Container(
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
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'Customer',
                                style: TextStyle(
                                  fontSize: 10.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Contact',
                                style: TextStyle(
                                  fontSize: 10.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Credit Limit',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 10.2,
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
                                  fontSize: 10.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            SizedBox(width: 72),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: customers.length,
                            itemBuilder: (context, index) {
                              final customer = customers[index];
                              return _CustomerCard(
                                customer: customer,
                                currency: _money,
                                canEdit: _canManage && !customer.isWalkIn,
                                onEdit: () => _editCustomer(customer),
                                onStatement: () => _openStatement(customer),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
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

class _CustomerCard extends StatelessWidget {
  final Customer customer;

  final String Function(double) currency;

  final bool canEdit;

  final VoidCallback onEdit;
  final VoidCallback onStatement;

  const _CustomerCard({
    required this.customer,
    required this.currency,
    required this.canEdit,
    required this.onEdit,
    required this.onStatement,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final location = [
      customer.city,
      customer.state,
    ].where((value) => value != null && value.isNotEmpty).join(', ');

    return Container(
      constraints: const BoxConstraints(minHeight: 55),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: customer.isWalkIn
            ? scheme.primaryContainer.withValues(alpha: .12)
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    customer.isWalkIn
                        ? Icons.storefront_outlined
                        : Icons.person_outline,
                    size: 16,
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
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        [
                          customer.publicId,
                          customer.contactPerson ?? '',
                          location,
                        ].where((e) => e.isNotEmpty).join(' | '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.9,
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
                  customer.phone ?? 'No phone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.3),
                ),
                Text(
                  customer.email ?? customer.taxNumber ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              currency(customer.creditLimit),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              customer.isWalkIn ? 'DEFAULT' : customer.status.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: customer.isActive
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Statement',
                  visualDensity: VisualDensity.compact,
                  onPressed: onStatement,
                  icon: const Icon(Icons.receipt_long_outlined, size: 14),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerFormDialog extends StatefulWidget {
  final ClientSession session;
  final Customer? customer;

  const _CustomerFormDialog({required this.session, this.customer});

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final CustomerService _service = CustomerService();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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

  late final TextEditingController _creditController;

  late final TextEditingController _notesController;

  String _status = 'active';

  bool _saving = false;

  String? _error;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();

    final customer = widget.customer;

    _nameController = TextEditingController(text: customer?.name ?? '');

    _contactController = TextEditingController(
      text: customer?.contactPerson ?? '',
    );

    _phoneController = TextEditingController(text: customer?.phone ?? '');

    _emailController = TextEditingController(text: customer?.email ?? '');

    _taxController = TextEditingController(text: customer?.taxNumber ?? '');

    _address1Controller = TextEditingController(
      text: customer?.addressLine1 ?? '',
    );

    _address2Controller = TextEditingController(
      text: customer?.addressLine2 ?? '',
    );

    _cityController = TextEditingController(text: customer?.city ?? '');

    _stateController = TextEditingController(text: customer?.state ?? 'Kerala');

    _postalController = TextEditingController(text: customer?.postalCode ?? '');

    _countryController = TextEditingController(
      text: customer?.country ?? 'India',
    );

    _creditController = TextEditingController(
      text: customer == null ? '0' : customer.creditLimit.toStringAsFixed(2),
    );

    _notesController = TextEditingController(text: customer?.notes ?? '');

    _status = customer?.status ?? 'active';
  }

  String? _requiredName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Customer name is required.';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final creditLimit = double.tryParse(_creditController.text.trim());

    if (creditLimit == null || creditLimit < 0) {
      setState(() {
        _error = 'Enter a valid credit limit.';
      });

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_editing) {
        await _service.updateCustomer(
          tenantId: widget.session.business.id,

          customerId: widget.customer!.id,

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

          creditLimit: creditLimit,

          notes: _notesController.text,

          status: _status,
        );
      } else {
        await _service.createCustomer(
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

          creditLimit: creditLimit,

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
    _creditController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit Customer' : 'Add Customer'),

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

                    validator: _requiredName,

                    decoration: const InputDecoration(
                      labelText: 'Customer Name *',

                      hintText: 'Rahman Auto Works',

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

                _twoFields(
                  TextFormField(
                    controller: _taxController,

                    enabled: !_saving,

                    textCapitalization: TextCapitalization.characters,

                    decoration: const InputDecoration(
                      labelText: 'GSTIN / Tax ID',

                      border: OutlineInputBorder(),
                    ),
                  ),

                  TextFormField(
                    controller: _creditController,

                    enabled: !_saving,

                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),

                    decoration: const InputDecoration(
                      labelText: 'Credit Limit',

                      prefixText: '₹ ',

                      border: OutlineInputBorder(),
                    ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),

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
                : 'Create Customer',
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
