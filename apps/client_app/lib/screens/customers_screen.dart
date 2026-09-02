import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';
import '../services/location_scope_service.dart';
import '../widgets/customer_account_dialog.dart';
import 'party_statement_screen.dart';
import 'customer_accounts_screen.dart';
import 'customer_crm_screen.dart';

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

  Future<void> _openReceivables() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerAccountsScreen(session: widget.session),
      ),
    );
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

  Future<void> _openAccount(Customer customer) async {
    if (customer.isWalkIn) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerAccountDialog(
        tenantId: widget.session.business.id,
        customerId: customer.id,
        customerName: customer.name,
        currencyCode: widget.session.currencyCode,
        locationId: LocationScopeService.currentForCreate(widget.session),
        deviceId: widget.session.device?.deviceId,
        canReceive:
            widget.session.hasRole('owner') ||
            widget.session.hasPermission('payments.receive') ||
            widget.session.hasPermission('sales.manage'),
      ),
    );
  }

  Future<void> _openCrm(Customer customer) async {
    if (customer.isWalkIn) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerCrmScreen(session: widget.session, customer: customer),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.all(14),

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
                      'Customers',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text('Manage customers and sales accounts'),
                  ],
                ),
              ),

              OutlinedButton.icon(
                onPressed: _openReceivables,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Receivables'),
              ),
              if (_canManage) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Customer'),
                ),
              ],
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
              hintText: 'Search ID, name, phone, GSTIN, city...',

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
                        const Icon(Icons.error_outline, size: 56),

                        const SizedBox(height: 16),

                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 18),

                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final all = snapshot.data ?? [];

                final customers = _filter(all);

                if (customers.isEmpty) {
                  return const Center(child: Text('No customers found.'));
                }

                return RefreshIndicator(
                  onRefresh: _refresh,

                  child: ListView.separated(
                    itemCount: customers.length,

                    separatorBuilder: (_, _) => const SizedBox(height: 10),

                    itemBuilder: (context, index) {
                      final customer = customers[index];

                      return _CustomerCard(
                        customer: customer,

                        currency: _money,

                        canEdit: _canManage && !customer.isWalkIn,

                        onEdit: () => _editCustomer(customer),
                        onStatement: () => _openStatement(customer),
                        onAccount: () => _openAccount(customer),
                        onCrm: () => _openCrm(customer),
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

class _CustomerCard extends StatelessWidget {
  final Customer customer;

  final String Function(double) currency;

  final bool canEdit;

  final VoidCallback onEdit;
  final VoidCallback onStatement;
  final VoidCallback onAccount;
  final VoidCallback onCrm;

  const _CustomerCard({
    required this.customer,
    required this.currency,
    required this.canEdit,
    required this.onEdit,
    required this.onStatement,
    required this.onAccount,
    required this.onCrm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: customer.isWalkIn ? Colors.indigo.shade50 : Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: customer.isWalkIn
              ? Colors.indigo.shade100
              : Colors.grey.shade200,
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,

            decoration: BoxDecoration(
              color: customer.isWalkIn ? Colors.white : Colors.blue.shade50,

              borderRadius: BorderRadius.circular(13),
            ),

            child: Icon(
              customer.isWalkIn
                  ? Icons.storefront_outlined
                  : Icons.person_outline,

              color: customer.isWalkIn ? Colors.indigo : null,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            flex: 3,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        customer.name,

                        style: const TextStyle(
                          fontSize: 16,

                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    if (customer.isWalkIn) ...[
                      const SizedBox(width: 8),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),

                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,

                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: const Text(
                          'DEFAULT',

                          style: TextStyle(
                            fontSize: 9,

                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 3),
                if (customer.publicId.isNotEmpty)
                  Text(
                    'Customer ID: ${customer.publicId}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade600,
                    ),
                  ),
                const SizedBox(height: 3),

                Text(
                  customer.contactPerson ??
                      (customer.isWalkIn
                          ? 'Counter sales customer'
                          : 'No contact person'),

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
                  customer.phone ?? 'No phone',

                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),

                if (customer.email != null)
                  Text(
                    customer.email!,

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
                  customer.taxNumber ?? 'No Tax ID',

                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),

                Text(
                  [customer.city, customer.state]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(', '),

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
                  'Credit Limit',

                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 3),

                Text(
                  currency(customer.creditLimit),

                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),

            decoration: BoxDecoration(
              color: customer.isActive
                  ? Colors.green.shade50
                  : Colors.grey.shade100,

              borderRadius: BorderRadius.circular(20),
            ),

            child: Text(
              customer.status.toUpperCase(),

              style: TextStyle(
                fontSize: 10,

                fontWeight: FontWeight.bold,

                color: customer.isActive
                    ? Colors.green.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ),

          const SizedBox(width: 8),
          if (!customer.isWalkIn)
            IconButton(
              tooltip: 'Customer CRM',
              onPressed: onCrm,
              icon: const Icon(Icons.people_alt_outlined),
            ),
          if (!customer.isWalkIn)
            IconButton(
              tooltip: 'Customer Account / Receive Payment',
              onPressed: onAccount,
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          IconButton(
            tooltip: 'Customer Statement',
            onPressed: onStatement,
            icon: const Icon(Icons.receipt_long_outlined),
          ),

          if (canEdit) ...[
            const SizedBox(width: 10),

            IconButton(
              tooltip: 'Edit Customer',

              onPressed: onEdit,

              icon: const Icon(Icons.edit_outlined),
            ),
          ],
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
