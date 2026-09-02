import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gst_compliance_v520_service.dart';

/// THQ ERP v5.2 GST & Compliance workspace.
///
/// This screen intentionally:
/// - performs no GST calculation in Flutter;
/// - never falls back to v5.1 transaction RPCs;
/// - treats legacy_unverified evidence as read-only;
/// - exposes GST Return preview only;
/// - keeps E-Invoice / E-Way Bill provider actions locked until the GSP/IRP phase.
class GstComplianceV520Screen extends StatefulWidget {
  const GstComplianceV520Screen({
    super.key,
    required this.service,
    this.title = 'GST & Compliance',
  });

  factory GstComplianceV520Screen.fromSupabase({
    Key? key,
    required SupabaseClient client,
    required String tenantId,
    String title = 'GST & Compliance',
  }) {
    return GstComplianceV520Screen(
      key: key,
      title: title,
      service: GstComplianceV520Service(client: client, tenantId: tenantId),
    );
  }

  final GstComplianceV520Service service;
  final String title;

  @override
  State<GstComplianceV520Screen> createState() =>
      _GstComplianceV520ScreenState();
}

class _GstComplianceV520ScreenState extends State<GstComplianceV520Screen> {
  late final GstComplianceV520Controller _controller;

  bool _loading = true;
  Object? _error;
  String _selectedTab = 'overview';

  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _registrations = const [];
  List<Map<String, dynamic>> _productProfiles = const [];
  List<Map<String, dynamic>> _partyProfiles = const [];

  Map<String, dynamic>? _transactions;
  Map<String, dynamic>? _taxSummary;
  Map<String, dynamic>? _accountingHealth;
  Map<String, dynamic>? _accountingControl;
  Map<String, dynamic>? _returnsPreview;

  String _productSearch = '';
  String _partySearch = '';
  String _partyType = 'customer';

  String _transactionSearch = '';
  String _transactionSourceType = '';
  String _transactionEvidence = 'all';
  int _transactionOffset = 0;
  static const int _transactionPageSize = 50;

  @override
  void initState() {
    super.initState();
    _controller = GstComplianceV520Controller(widget.service);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _controller.load();
      final lookup = await widget.service.loadSetupLookups(
        kind: 'locations',
        limit: 500,
      );

      if (!mounted) return;
      setState(() {
        _locations = _list(lookup['locations']);
        _transactions = data.documents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refreshWorkspace() async {
    await _guard(() async {
      final data = await _controller.refresh();
      final lookup = await widget.service.loadSetupLookups(
        kind: 'locations',
        limit: 500,
      );

      if (!mounted) return;
      setState(() {
        _locations = _list(lookup['locations']);
        _transactions = data.documents;

        // Clear lazy tab data so the next open gets a fresh server result.
        _registrations = const [];
        _productProfiles = const [];
        _partyProfiles = const [];
        _taxSummary = null;
        _accountingHealth = null;
        _accountingControl = null;
        _returnsPreview = null;
      });

      await _loadSelectedTab(force: true);
    });
  }

  Future<void> _loadSelectedTab({bool force = false}) async {
    switch (_selectedTab) {
      case 'overview':
        return;
      case 'registrations':
        if (force || _registrations.isEmpty) {
          await _loadRegistrations();
        }
        return;
      case 'products':
        if (force || _productProfiles.isEmpty) {
          await _loadProductProfiles();
        }
        return;
      case 'parties':
        if (force || _partyProfiles.isEmpty) {
          await _loadPartyProfiles();
        }
        return;
      case 'transactions':
        if (force || _transactions == null) {
          await _loadTransactions(resetPage: false);
        }
        return;
      case 'tax_summary':
        if (force || _taxSummary == null) {
          await _loadTaxSummary();
        }
        return;
      case 'accounting':
        if (force || _accountingHealth == null || _accountingControl == null) {
          await _loadAccounting();
        }
        return;
      case 'returns':
        if (force || _returnsPreview == null) {
          await _loadReturnsPreview();
        }
        return;
      case 'einvoice':
      case 'ewaybill':
        return;
    }
  }

  Future<void> _selectTab(String key) async {
    final tab = widget.service.uiContract.tab(key);
    final accessible = _tabAccessible(tab);

    if (!tab.enabled || !accessible) {
      if (mounted) {
        _toast(
          tab.data['reason']?.toString() == 'provider_not_configured'
              ? '${tab.label} is locked until GSP/IRP provider integration.'
              : 'You do not have access to ${tab.label}.',
        );
      }
      return;
    }

    setState(() {
      _selectedTab = key;
      _error = null;
    });

    await _guard(() => _loadSelectedTab());
  }

  // ---------------------------------------------------------------------------
  // DATA LOADERS
  // ---------------------------------------------------------------------------

  Future<void> _loadRegistrations() async {
    final rows = await widget.service.listRegistrations();
    if (!mounted) return;
    setState(() => _registrations = rows);
  }

  Future<void> _loadProductProfiles() async {
    final rows = await widget.service.listProductProfiles(
      query: _productSearch,
      limit: 500,
    );
    if (!mounted) return;
    setState(() => _productProfiles = rows);
  }

  Future<void> _loadPartyProfiles() async {
    final rows = await widget.service.listPartyProfiles(
      partyType: _partyType,
      query: _partySearch,
      limit: 300,
    );
    if (!mounted) return;
    setState(() => _partyProfiles = rows);
  }

  Future<void> _loadTransactions({bool resetPage = true}) async {
    if (resetPage) _transactionOffset = 0;

    final data = await widget.service.listDocuments(
      from: _controller.from,
      to: _controller.to,
      locationId: _controller.locationId,
      sourceType: _emptyToNull(_transactionSourceType),
      evidenceStatus: _transactionEvidence,
      query: _transactionSearch,
      limit: _transactionPageSize,
      offset: _transactionOffset,
    );

    if (!mounted) return;
    setState(() => _transactions = data);
  }

  Future<void> _loadTaxSummary() async {
    final data = await widget.service.loadTaxSummary(
      from: _controller.from,
      to: _controller.to,
      locationId: _controller.locationId,
    );

    if (!mounted) return;
    setState(() => _taxSummary = data);
  }

  Future<void> _loadAccounting() async {
    final health = await widget.service.loadAccountingHealth();
    final control = await widget.service.loadAccountingControl(
      from: _controller.from,
      to: _controller.to,
      locationId: _controller.locationId,
    );

    if (!mounted) return;
    setState(() {
      _accountingHealth = health;
      _accountingControl = control;
    });
  }

  Future<void> _loadReturnsPreview() async {
    final data = await widget.service.loadReturnsPreview(
      from: _controller.from,
      to: _controller.to,
      locationId: _controller.locationId,
    );

    if (!mounted) return;
    setState(() => _returnsPreview = data);
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && !_controller.service.isInitialized) {
      return _FatalError(error: _error!, onRetry: _loadInitial);
    }

    final contract = widget.service.uiContract;
    final tabs = contract.tabs.where(_shouldShowTab).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;

        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              _buildHeader(wide),
              if (!wide) _buildCompactTabPicker(tabs),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      SizedBox(width: 206, child: _buildNavigationRail(tabs)),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool wide) {
    final selectedLocation = _locationById(_controller.locationId);
    final rangeLabel =
        '${_date(_controller.from)}  â†’  ${_date(_controller.to)}';

    return Material(
      elevation: 0.6,
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 18 : 12, 10, wide ? 18 : 12, 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 250),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 21),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _StatusPill(
                    label: '5.2 Foundation',
                    tone: _PillTone.info,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickPeriod,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(rangeLabel),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_controller.locationId ?? ''),
                initialValue: _controller.locationId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All locations'),
                  ),
                  ..._locations.map(
                    (row) => DropdownMenuItem(
                      value: _s(row['id']),
                      child: Text(
                        _s(row['name'], fallback: 'Location'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) async {
                  _controller.locationId = _emptyToNull(value);
                  await _guard(() async {
                    await _controller.load();
                    if (!mounted) return;
                    setState(() {
                      _transactions = _controller.data?.documents;
                      _taxSummary = null;
                      _accountingControl = null;
                      _returnsPreview = null;
                    });
                    await _loadSelectedTab(force: true);
                  });
                },
              ),
            ),
            if (selectedLocation != null &&
                selectedLocation['registration_id'] == null)
              const _StatusPill(
                label: 'GST registration not mapped',
                tone: _PillTone.warning,
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshWorkspace,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationRail(List<GstUiTabV520> tabs) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0.4,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _NavTile(
                label: tab.label,
                icon: _tabIcon(tab.key),
                selected: tab.key == _selectedTab,
                locked: !tab.enabled || !_tabAccessible(tab),
                onTap: () => _selectTab(tab.key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactTabPicker(List<GstUiTabV520> tabs) {
    final selected = tabs.any((tab) => tab.key == _selectedTab)
        ? _selectedTab
        : tabs.first.key;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: DropdownButtonFormField<String>(
        key: ValueKey(selected),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'GST workspace',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: tabs
            .map(
              (tab) => DropdownMenuItem(
                value: tab.key,
                enabled: tab.enabled && _tabAccessible(tab),
                child: Row(
                  children: [
                    Icon(_tabIcon(tab.key), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tab.label)),
                    if (!tab.enabled || !_tabAccessible(tab))
                      const Icon(Icons.lock_outline, size: 16),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) _selectTab(value);
        },
      ),
    );
  }

  Widget _buildContent() {
    final error = _error;

    return Column(
      children: [
        if (error != null)
          _InlineError(
            error: error,
            onClose: () => setState(() => _error = null),
          ),
        Expanded(
          child: switch (_selectedTab) {
            'overview' => _buildOverview(),
            'registrations' => _buildRegistrations(),
            'products' => _buildProducts(),
            'parties' => _buildParties(),
            'transactions' => _buildTransactions(),
            'tax_summary' => _buildTaxSummary(),
            'accounting' => _buildAccounting(),
            'returns' => _buildReturns(),
            'einvoice' => _buildProviderLocked('E-Invoice'),
            'ewaybill' => _buildProviderLocked('E-Way Bill'),
            _ => _buildOverview(),
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildOverview() {
    final data = _controller.data;
    if (data == null) return const SizedBox.shrink();

    final workspace = data.workspace;
    final readiness = data.readiness;
    final dashboard = _map(workspace['dashboard']);
    final setup = _map(workspace['setup']);
    final coverage = _map(workspace['coverage']);
    final provider = _map(workspace['provider']);
    final accounting = _map(workspace['accounting']);
    final blockers = _list(readiness['blockers']);

    return _Page(
      title: 'GST Overview',
      subtitle:
          'Server-authoritative GST readiness, evidence coverage and accounting control.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _selectTab('transactions'),
          icon: const Icon(Icons.list_alt_outlined, size: 18),
          label: const Text('Transactions'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResponsiveCards(
            children: [
              _MetricCard(
                label: 'Compliance status',
                value: blockers.isEmpty
                    ? 'Ready'
                    : '${blockers.length} blocker(s)',
                icon: blockers.isEmpty
                    ? Icons.verified_outlined
                    : Icons.warning_amber_outlined,
                tone: blockers.isEmpty ? _PillTone.success : _PillTone.warning,
              ),
              _MetricCard(
                label: 'Authoritative documents',
                value: _firstNonEmpty([
                  dashboard['authoritative_documents'],
                  dashboard['authoritative_count'],
                  dashboard['document_count'],
                  0,
                ]).toString(),
                icon: Icons.fact_check_outlined,
                tone: _PillTone.success,
              ),
              _MetricCard(
                label: 'Legacy evidence',
                value: _firstNonEmpty([
                  dashboard['legacy_unverified_documents'],
                  dashboard['legacy_count'],
                  0,
                ]).toString(),
                icon: Icons.history_outlined,
                tone: _PillTone.warning,
              ),
              _MetricCard(
                label: 'Provider integration',
                value: _truthy(provider['ready']) ? 'Ready' : 'Not enabled',
                icon: Icons.cloud_outlined,
                tone: _truthy(provider['ready'])
                    ? _PillTone.success
                    : _PillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TwoColumn(
            left: _SectionCard(
              title: 'Setup readiness',
              icon: Icons.tune_outlined,
              child: _KeyValueMap(data: setup),
            ),
            right: _SectionCard(
              title: 'GST coverage',
              icon: Icons.inventory_2_outlined,
              child: _KeyValueMap(data: coverage),
            ),
          ),
          const SizedBox(height: 12),
          _TwoColumn(
            left: _SectionCard(
              title: 'Accounting health',
              icon: Icons.account_balance_outlined,
              child: _KeyValueMap(data: accounting),
            ),
            right: _SectionCard(
              title: 'Provider state',
              icon: Icons.hub_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _StatusPill(
                    label: 'Submission disabled',
                    tone: _PillTone.neutral,
                  ),
                  const SizedBox(height: 8),
                  _KeyValueMap(data: provider),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Readiness blockers',
            icon: Icons.rule_folder_outlined,
            child: blockers.isEmpty
                ? const _EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No GST readiness blockers',
                    message:
                        'Current configuration is ready for the enabled v5.2 compliance features.',
                  )
                : Column(
                    children: [
                      for (final blocker in blockers)
                        _BlockerTile(
                          blocker: blocker,
                          onOpen: () => _openBlocker(blocker),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openBlocker(Map<String, dynamic> blocker) {
    final code =
        '${blocker['value']} ${blocker['code']} ${blocker['type']} ${blocker['area']}'
            .toLowerCase();

    if (code.contains('registration') || code.contains('location')) {
      _selectTab('registrations');
    } else if (code.contains('product') ||
        code.contains('hsn') ||
        code.contains('sac')) {
      _selectTab('products');
    } else if (code.contains('party') ||
        code.contains('customer') ||
        code.contains('supplier') ||
        code.contains('gstin')) {
      _selectTab('parties');
    } else if (code.contains('account')) {
      _selectTab('accounting');
    } else {
      _selectTab('overview');
    }
  }

  // ---------------------------------------------------------------------------
  // REGISTRATIONS
  // ---------------------------------------------------------------------------

  Widget _buildRegistrations() {
    return _Page(
      title: 'GST Registrations',
      subtitle:
          'Maintain legal GST registrations and assign each business location to the correct registration.',
      actions: [
        FilledButton.icon(
          onPressed: widget.service.can('configure')
              ? () => _openRegistrationDialog()
              : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add registration'),
        ),
        OutlinedButton.icon(
          onPressed: widget.service.can('configure')
              ? _openLocationMappingDialog
              : null,
          icon: const Icon(Icons.add_location_alt_outlined, size: 18),
          label: const Text('Map location'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'Location â†’ registration',
            icon: Icons.location_on_outlined,
            child: _locations.isEmpty
                ? const _EmptyState(
                    icon: Icons.location_off_outlined,
                    title: 'No active locations',
                    message: 'No GST-configurable business locations found.',
                  )
                : _CompactTable(
                    columns: const [
                      'Location',
                      'Type',
                      'GSTIN',
                      'Legal name',
                      'Status',
                    ],
                    rows: [
                      for (final row in _locations)
                        [
                          _s(row['name']),
                          _s(row['location_type']),
                          _s(row['gstin'], fallback: 'â€”'),
                          _s(row['registration_legal_name'], fallback: 'â€”'),
                          row['registration_id'] == null
                              ? 'Not mapped'
                              : 'Mapped',
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Registrations',
            icon: Icons.badge_outlined,
            child: _registrations.isEmpty
                ? _EmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No GST registration configured',
                    message:
                        'Add the legal GST registration, then map each business location.',
                    action: widget.service.can('configure')
                        ? FilledButton(
                            onPressed: _openRegistrationDialog,
                            child: const Text('Add registration'),
                          )
                        : null,
                  )
                : Column(
                    children: [
                      for (final row in _registrations)
                        _RegistrationCard(
                          row: row,
                          onEdit: widget.service.can('configure')
                              ? () => _openRegistrationDialog(existing: row)
                              : null,
                          onConfig: () => _showRegistrationConfig(row),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRegistrationDialog({Map<String, dynamic>? existing}) async {
    final result = await showDialog<_RegistrationFormValue>(
      context: context,
      builder: (context) => _RegistrationDialog(existing: existing),
    );
    if (result == null) return;

    await _guard(() async {
      await widget.service.saveRegistration(
        id: result.id,
        gstin: result.gstin,
        legalName: result.legalName,
        tradeName: result.tradeName,
        registrationType: result.registrationType,
        stateCode: result.stateCode,
        addressLine1: result.addressLine1,
        addressLine2: result.addressLine2,
        city: result.city,
        postalCode: result.postalCode,
        einvoiceEnabled: result.einvoiceEnabled,
        ewaybillEnabled: result.ewaybillEnabled,
        returnsEnabled: result.returnsEnabled,
        providerKey: result.providerKey,
        active: result.active,
        effectiveFrom: result.effectiveFrom,
      );
      await _loadRegistrations();
      await _reloadLocations();
      await _controller.refresh();
      _toast('GST registration saved.');
    });
  }

  Future<void> _showRegistrationConfig(Map<String, dynamic> row) async {
    await _guard(() async {
      final id = _firstText(row, ['id', 'registration_id']);
      final config = await widget.service.loadRegistrationConfig(
        registrationId: id,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _JsonDetailDialog(
          title: 'Registration configuration',
          data: config,
        ),
      );
    });
  }

  Future<void> _openLocationMappingDialog() async {
    await _guard(() async {
      if (_registrations.isEmpty) {
        await _loadRegistrations();
      }
      await _reloadLocations();

      if (!mounted) return;

      final value = await showDialog<_LocationMappingValue>(
        context: context,
        builder: (context) => _LocationMappingDialog(
          locations: _locations,
          registrations: _registrations,
        ),
      );

      if (value == null) return;

      await widget.service.mapLocationToRegistration(
        locationId: value.locationId,
        registrationId: value.registrationId,
        effectiveFrom: value.effectiveFrom,
      );

      await _reloadLocations();
      await _controller.refresh();
      _toast('Location GST registration mapped.');
    });
  }

  Future<void> _reloadLocations() async {
    final lookup = await widget.service.loadSetupLookups(
      kind: 'locations',
      limit: 500,
    );
    if (!mounted) return;
    setState(() => _locations = _list(lookup['locations']));
  }

  // ---------------------------------------------------------------------------
  // PRODUCT GST
  // ---------------------------------------------------------------------------

  Widget _buildProducts() {
    return _Page(
      title: 'Product GST',
      subtitle:
          'HSN/SAC, taxability, GST rate, cess, tax-inclusive and reverse-charge configuration.',
      actions: [
        FilledButton.icon(
          onPressed: widget.service.can('manage')
              ? () => _openProductDialog()
              : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Configure product'),
        ),
      ],
      filters: _SearchBar(
        hint: 'Search product, SKU or HSN/SAC',
        initialValue: _productSearch,
        onSearch: (value) async {
          _productSearch = value;
          await _guard(_loadProductProfiles);
        },
      ),
      child: _productProfiles.isEmpty
          ? const _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No matching GST product profiles',
              message:
                  'Configure GST for active product variants using the Add action.',
            )
          : Column(
              children: [
                for (final row in _productProfiles)
                  _ProductProfileCard(
                    row: row,
                    onEdit: widget.service.can('manage')
                        ? () => _openProductDialog(existing: row)
                        : null,
                  ),
              ],
            ),
    );
  }

  Future<void> _openProductDialog({Map<String, dynamic>? existing}) async {
    Map<String, dynamic>? selectedProduct;

    if (existing == null) {
      selectedProduct = await _pickLookupEntity(
        kind: 'products',
        title: 'Select product variant',
        itemBuilder: (row) {
          final configured = _truthy(row['configured']);
          final title = [
            _s(row['product_name']),
            _s(row['variant_name']),
          ].where((e) => e.isNotEmpty && e != 'â€”').join(' â€¢ ');
          final subtitle = [
            _s(row['sku'], fallback: ''),
            configured ? 'GST configured' : 'Not configured',
            _s(row['hsn_sac'], fallback: ''),
          ].where((e) => e.isNotEmpty).join('  |  ');

          return ListTile(
            dense: true,
            leading: Icon(
              configured ? Icons.verified_outlined : Icons.inventory_2_outlined,
            ),
            title: Text(title),
            subtitle: Text(subtitle),
          );
        },
      );
      if (selectedProduct == null) return;
    }

    if (!mounted) return;
    final result = await showDialog<_ProductGstFormValue>(
      context: context,
      builder: (context) => _ProductGstDialog(
        existing: existing,
        selectedProduct: selectedProduct,
        rates: _list(_controller.data?.masters['rates']),
      ),
    );
    if (result == null) return;

    await _guard(() async {
      await widget.service.saveProductProfile(
        variantId: result.variantId,
        supplyKind: result.supplyKind,
        hsnSac: result.hsnSac,
        taxability: result.taxability,
        gstRate: result.gstRate,
        cessRate: result.cessRate,
        cessPerUnit: result.cessPerUnit,
        taxInclusive: result.taxInclusive,
        reverseCharge: result.reverseCharge,
        notes: result.notes,
        effectiveFrom: result.effectiveFrom,
      );

      await _loadProductProfiles();
      await _controller.refresh();
      _toast('Product GST profile saved.');
    });
  }

  // ---------------------------------------------------------------------------
  // PARTY GST
  // ---------------------------------------------------------------------------

  Widget _buildParties() {
    return _Page(
      title: 'Party GST',
      subtitle:
          'Customer and supplier GST registration profiles used by the central v5.2 tax engine.',
      actions: [
        FilledButton.icon(
          onPressed: widget.service.can('manage') ? _openPartyDialog : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Configure party'),
        ),
      ],
      filters: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'customer',
                label: Text('Customers'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: 'supplier',
                label: Text('Suppliers'),
                icon: Icon(Icons.local_shipping_outlined),
              ),
            ],
            selected: {_partyType},
            onSelectionChanged: (value) async {
              _partyType = value.first;
              await _guard(_loadPartyProfiles);
            },
          ),
          SizedBox(
            width: 340,
            child: _SearchBar(
              hint: 'Search name, GSTIN or legal name',
              initialValue: _partySearch,
              onSearch: (value) async {
                _partySearch = value;
                await _guard(_loadPartyProfiles);
              },
            ),
          ),
        ],
      ),
      child: _partyProfiles.isEmpty
          ? const _EmptyState(
              icon: Icons.people_outline,
              title: 'No matching party GST profiles',
              message:
                  'Use Configure party to select an active customer or supplier.',
            )
          : Column(
              children: [
                for (final row in _partyProfiles)
                  _PartyProfileCard(
                    row: row,
                    onEdit: widget.service.can('manage')
                        ? () => _openPartyDialog(existing: row)
                        : null,
                  ),
              ],
            ),
    );
  }

  Future<void> _openPartyDialog({Map<String, dynamic>? existing}) async {
    Map<String, dynamic>? selectedParty;

    if (existing == null) {
      selectedParty = await _pickLookupEntity(
        kind: _partyType == 'supplier' ? 'suppliers' : 'customers',
        title: _partyType == 'supplier' ? 'Select supplier' : 'Select customer',
        itemBuilder: (row) {
          return ListTile(
            dense: true,
            leading: Icon(
              _truthy(row['configured'])
                  ? Icons.verified_outlined
                  : Icons.person_outline,
            ),
            title: Text(_s(row['party_name'])),
            subtitle: Text(
              [
                _s(row['gstin'], fallback: ''),
                _truthy(row['configured'])
                    ? 'GST configured'
                    : 'Not configured',
              ].where((e) => e.isNotEmpty).join('  |  '),
            ),
          );
        },
      );
      if (selectedParty == null) return;
    }

    if (!mounted) return;
    final result = await showDialog<_PartyGstFormValue>(
      context: context,
      builder: (context) => _PartyGstDialog(
        existing: existing,
        selectedParty: selectedParty,
        states: _list(_controller.data?.masters['states']),
      ),
    );
    if (result == null) return;

    await _guard(() async {
      await widget.service.savePartyProfile(
        id: result.id,
        partyType: result.partyType,
        partyId: result.partyId,
        registrationType: result.registrationType,
        gstin: result.gstin,
        legalName: result.legalName,
        tradeName: result.tradeName,
        stateCode: result.stateCode,
        placeOfSupplyCode: result.placeOfSupplyCode,
        addressLine1: result.addressLine1,
        addressLine2: result.addressLine2,
        city: result.city,
        postalCode: result.postalCode,
        country: result.country,
        active: result.active,
      );

      _partyType = result.partyType;
      await _loadPartyProfiles();
      await _controller.refresh();
      _toast('Party GST profile saved.');
    });
  }

  Future<Map<String, dynamic>?> _pickLookupEntity({
    required String kind,
    required String title,
    required Widget Function(Map<String, dynamic> row) itemBuilder,
  }) async {
    final initial = await widget.service.loadSetupLookups(
      kind: kind,
      limit: 200,
    );

    if (!mounted) return null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LookupDialog(
        title: title,
        initialRows: _list(initial[kind]),
        load: (query) async {
          final result = await widget.service.loadSetupLookups(
            kind: kind,
            query: query,
            limit: 200,
          );
          return _list(result[kind]);
        },
        itemBuilder: itemBuilder,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRANSACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildTransactions() {
    final data = _transactions ?? const <String, dynamic>{};
    final items = _list(data['items'] ?? data['rows']);
    final total = _integer(data['total_count'] ?? data['total']);
    final canPrevious = _transactionOffset > 0;
    final canNext = _transactionOffset + items.length < total;

    final sourceTypes = [
      '',
      ..._stringList(_controller.data?.defaults['source_types']),
    ];

    return _Page(
      title: 'GST Transactions',
      subtitle:
          'Immutable authoritative GST evidence plus read-only legacy_unverified history.',
      filters: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 290,
            child: _SearchBar(
              hint: 'Search document number',
              initialValue: _transactionSearch,
              onSearch: (value) async {
                _transactionSearch = value;
                await _guard(() => _loadTransactions());
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                sourceTypes.contains(_transactionSourceType)
                    ? _transactionSourceType
                    : '',
              ),
              initialValue: sourceTypes.contains(_transactionSourceType)
                  ? _transactionSourceType
                  : '',
              decoration: const InputDecoration(
                labelText: 'Source',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final value in sourceTypes)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      value.isEmpty ? 'All sources' : _labelize(value),
                    ),
                  ),
              ],
              onChanged: (value) async {
                _transactionSourceType = value ?? '';
                await _guard(() => _loadTransactions());
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey(_transactionEvidence),
              initialValue: _transactionEvidence,
              decoration: const InputDecoration(
                labelText: 'Evidence',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All evidence')),
                DropdownMenuItem(
                  value: 'authoritative',
                  child: Text('Authoritative'),
                ),
                DropdownMenuItem(
                  value: 'legacy_unverified',
                  child: Text('Legacy unverified'),
                ),
              ],
              onChanged: (value) async {
                _transactionEvidence = value ?? 'all';
                await _guard(() => _loadTransactions());
              },
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'Documents',
            icon: Icons.receipt_long_outlined,
            trailing: Text('$total total'),
            child: items.isEmpty
                ? const _EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No GST documents found',
                    message: 'Change the date or transaction filters.',
                  )
                : Column(
                    children: [
                      for (final row in items)
                        _TransactionTile(
                          row: row,
                          onOpen: () => _openEvidence(row),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: canPrevious
                    ? () async {
                        _transactionOffset =
                            (_transactionOffset - _transactionPageSize)
                                .clamp(0, 1 << 31)
                                .toInt();
                        await _guard(() => _loadTransactions(resetPage: false));
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: canNext
                    ? () async {
                        _transactionOffset += _transactionPageSize;
                        await _guard(() => _loadTransactions(resetPage: false));
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
              const Spacer(),
              Text(
                total == 0
                    ? '0'
                    : '${_transactionOffset + 1}'
                          'â€“${_transactionOffset + items.length} of $total',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEvidence(Map<String, dynamic> row) async {
    final sourceType = _firstText(row, ['source_type', 'document_type']);
    final sourceId = _firstText(row, ['source_id', 'id']);

    if (sourceType.isEmpty || sourceId.isEmpty) {
      _toast('Document evidence reference is incomplete.');
      return;
    }

    await _guard(() async {
      final detail = await widget.service.loadDocumentEvidence(
        sourceType: sourceType,
        sourceId: sourceId,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _EvidenceDialog(data: detail),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // TAX SUMMARY / ACCOUNTING / RETURNS
  // ---------------------------------------------------------------------------

  Widget _buildTaxSummary() {
    final data = _taxSummary;
    return _Page(
      title: 'Tax Summary',
      subtitle:
          'Period summary generated from server-authoritative GST evidence.',
      child: data == null
          ? const Center(child: CircularProgressIndicator())
          : _JsonSections(data: data),
    );
  }

  Widget _buildAccounting() {
    final health = _accountingHealth;
    final control = _accountingControl;

    return _Page(
      title: 'GST Accounting',
      subtitle:
          'Component-journal health and GST-to-accounting reconciliation controls.',
      child: health == null || control == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _SectionCard(
                  title: 'Accounting health',
                  icon: Icons.monitor_heart_outlined,
                  child: _JsonSections(data: health),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Period control',
                  icon: Icons.balance_outlined,
                  child: _JsonSections(data: control),
                ),
              ],
            ),
    );
  }

  Widget _buildReturns() {
    final data = _returnsPreview;

    return _Page(
      title: 'GST Returns',
      subtitle:
          'Statutory preview only. Filing/submission is not enabled in this phase.',
      actions: const [
        _StatusPill(label: 'Preview only', tone: _PillTone.warning),
      ],
      child: data == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _NoticeCard(
                  icon: Icons.lock_outline,
                  title: 'Return submission is disabled',
                  message:
                      'THQ can prepare and review GST period data here. '
                      'GSP filing will be enabled only after the provider '
                      'sandbox, retry/recovery and audit controls are complete.',
                ),
                const SizedBox(height: 12),
                _JsonSections(data: data),
              ],
            ),
    );
  }

  Widget _buildProviderLocked(String feature) {
    return _Page(
      title: feature,
      subtitle: 'Provider integration is deliberately locked.',
      child: _NoticeCard(
        icon: Icons.lock_outline,
        title: '$feature is not enabled yet',
        message:
            'This v5.2 foundation does not call a GSP/IRP provider. '
            'There is no submission, IRN generation/cancellation, '
            'E-Way Bill generation or provider retry path in the Client UI.',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PERIOD / PERMISSION / ERROR HELPERS
  // ---------------------------------------------------------------------------

  Future<void> _pickPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2017, 7, 1),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: DateTimeRange(
        start: _controller.from,
        end: _controller.to,
      ),
    );

    if (range == null) return;

    await _guard(() async {
      await _controller.changePeriod(
        from: range.start,
        to: range.end,
        locationId: _controller.locationId,
      );

      if (!mounted) return;
      setState(() {
        _transactions = _controller.data?.documents;
        _taxSummary = null;
        _accountingControl = null;
        _returnsPreview = null;
      });

      await _loadSelectedTab(force: true);
    });
  }

  bool _shouldShowTab(GstUiTabV520 tab) {
    // Always surface the two future provider features as locked tiles.
    if (tab.key == 'einvoice' || tab.key == 'ewaybill') return true;

    // For all other tabs, hide inaccessible areas instead of rendering a
    // misleading empty page.
    return _tabAccessible(tab);
  }

  bool _tabAccessible(GstUiTabV520 tab) {
    final capability = _permissionCapability(tab.permission);
    if (capability == null) return true;
    return widget.service.can(capability);
  }

  String? _permissionCapability(String permission) {
    if (!permission.startsWith('gst_compliance.')) return null;
    return permission.substring('gst_compliance.'.length);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      if (mounted) {
        setState(() => _error = null);
      }
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? _locationById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final row in _locations) {
      if (_s(row['id']) == id) return row;
    }
    return null;
  }
}

// =============================================================================
// PAGE SHELL
// =============================================================================

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.filters,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? filters;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            if (filters != null) ...[const SizedBox(height: 12), filters!],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: locked
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
                    : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: locked
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
                        : null,
                  ),
                ),
              ),
              if (locked)
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// COMMON CARDS / TABLES / STATUS
// =============================================================================

enum _PillTone { success, warning, info, neutral, error }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _PillTone.success => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _PillTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _PillTone.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _PillTone.error => (scheme.errorContainer, scheme.onErrorContainer),
      _PillTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(
            label: switch (tone) {
              _PillTone.success => 'OK',
              _PillTone.warning => 'Check',
              _PillTone.info => 'Info',
              _PillTone.error => 'Error',
              _PillTone.neutral => 'Pending',
            },
            tone: tone,
          ),
        ],
      ),
    );
  }
}

class _ResponsiveCards extends StatelessWidget {
  const _ResponsiveCards({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.title,
    this.icon,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.35,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class _CompactTable extends StatelessWidget {
  const _CompactTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 46,
        columnSpacing: 24,
        horizontalMargin: 8,
        columns: [
          for (final column in columns)
            DataColumn(
              label: Text(
                column,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final value in row)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _KeyValueMap extends StatelessWidget {
  const _KeyValueMap({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No data');
    }

    return Column(
      children: [
        for (final entry in data.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    _labelize(entry.key),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Text(
                    _display(entry.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _JsonSections extends StatelessWidget {
  const _JsonSections({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scalar = <String, dynamic>{};
    final complex = <MapEntry<String, dynamic>>[];

    for (final entry in data.entries) {
      if (entry.value is Map || entry.value is List) {
        complex.add(entry);
      } else {
        scalar[entry.key] = entry.value;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scalar.isNotEmpty)
          _SectionCard(
            title: 'Summary',
            child: _KeyValueMap(data: scalar),
          ),
        for (final entry in complex) ...[
          if (scalar.isNotEmpty || entry != complex.first)
            const SizedBox(height: 10),
          _SectionCard(
            title: _labelize(entry.key),
            child: entry.value is Map
                ? _KeyValueMap(data: _map(entry.value))
                : _JsonList(values: _list(entry.value)),
          ),
        ],
      ],
    );
  }
}

class _JsonList extends StatelessWidget {
  const _JsonList({required this.values});

  final List<Map<String, dynamic>> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text('No items');
    }

    return Column(
      children: [
        for (final row in values)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(7),
            ),
            child: _KeyValueMap(data: row),
          ),
      ],
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.hint,
    required this.onSearch,
    this.initialValue = '',
  });

  final String hint;
  final String initialValue;
  final Future<void> Function(String value) onSearch;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 19),
        suffixIcon: IconButton(
          tooltip: 'Search',
          onPressed: () => widget.onSearch(_text.text.trim()),
          icon: const Icon(Icons.arrow_forward, size: 18),
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (value) => widget.onSearch(value.trim()),
    );
  }
}

// =============================================================================
// OVERVIEW BLOCKERS
// =============================================================================

class _BlockerTile extends StatelessWidget {
  const _BlockerTile({required this.blocker, required this.onOpen});

  final Map<String, dynamic> blocker;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = _firstText(blocker, [
      'message',
      'title',
      'code',
      'type',
      'value',
    ], fallback: 'GST readiness blocker');
    final detail = _firstText(blocker, [
      'detail',
      'hint',
      'area',
    ], fallback: '');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.warning_amber_outlined),
      title: Text(title),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

// =============================================================================
// REGISTRATION CARDS / FORM
// =============================================================================

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({required this.row, this.onEdit, this.onConfig});

  final Map<String, dynamic> row;
  final VoidCallback? onEdit;
  final VoidCallback? onConfig;

  @override
  Widget build(BuildContext context) {
    final gstin = _firstText(row, ['gstin']);
    final name = _firstText(row, [
      'legal_name',
      'trade_name',
    ], fallback: 'GST Registration');
    final active = row['active'] != false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0.15,
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusPill(
              label: active ? 'Active' : 'Inactive',
              tone: active ? _PillTone.success : _PillTone.neutral,
            ),
          ],
        ),
        subtitle: Text(
          [
            gstin,
            _labelize(_s(row['registration_type'], fallback: '')),
            _s(row['state_code'], fallback: ''),
          ].where((e) => e.isNotEmpty).join('  â€¢  '),
        ),
        trailing: Wrap(
          spacing: 0,
          children: [
            IconButton(
              tooltip: 'Configuration',
              onPressed: onConfig,
              icon: const Icon(Icons.tune_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationDialog extends StatefulWidget {
  const _RegistrationDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _gstin;
  late final TextEditingController _legal;
  late final TextEditingController _trade;
  late final TextEditingController _state;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _postal;
  late final TextEditingController _provider;

  String _type = 'regular';
  bool _einvoice = false;
  bool _ewaybill = false;
  bool _returns = true;
  bool _active = true;
  DateTime _effectiveFrom = DateTime.now();

  static const _types = [
    'regular',
    'composition',
    'casual',
    'sez',
    'isd',
    'tcs',
    'tds',
    'non_resident',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final row = widget.existing ?? const <String, dynamic>{};

    _gstin = TextEditingController(text: _s(row['gstin'], fallback: ''));
    _legal = TextEditingController(text: _s(row['legal_name'], fallback: ''));
    _trade = TextEditingController(text: _s(row['trade_name'], fallback: ''));
    _state = TextEditingController(text: _s(row['state_code'], fallback: ''));
    _address1 = TextEditingController(
      text: _s(row['address_line1'], fallback: ''),
    );
    _address2 = TextEditingController(
      text: _s(row['address_line2'], fallback: ''),
    );
    _city = TextEditingController(text: _s(row['city'], fallback: ''));
    _postal = TextEditingController(text: _s(row['postal_code'], fallback: ''));
    _provider = TextEditingController(
      text: _s(row['provider_key'], fallback: ''),
    );

    final type = _s(row['registration_type'], fallback: 'regular');
    _type = _types.contains(type) ? type : 'regular';
    _einvoice = _truthy(row['einvoice_enabled']);
    _ewaybill = _truthy(row['ewaybill_enabled']);
    _returns = row['returns_enabled'] != false;
    _active = row['active'] != false;
    _effectiveFrom = _tryDate(row['effective_from']) ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final controller in [
      _gstin,
      _legal,
      _trade,
      _state,
      _address1,
      _address2,
      _city,
      _postal,
      _provider,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Add GST registration'
            : 'Edit GST registration',
      ),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _field(
                  width: 320,
                  controller: _gstin,
                  label: 'GSTIN',
                  validator: _required,
                  capitalization: TextCapitalization.characters,
                ),
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Registration type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final type in _types)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_labelize(type)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                ),
                _field(
                  width: 430,
                  controller: _legal,
                  label: 'Legal name',
                  validator: _required,
                ),
                _field(width: 210, controller: _trade, label: 'Trade name'),
                _field(
                  width: 150,
                  controller: _state,
                  label: 'State code',
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!RegExp(r'^\d{2}$').hasMatch(text)) {
                      return '2-digit state code';
                    }
                    return null;
                  },
                ),
                _DateField(
                  width: 210,
                  label: 'Effective from',
                  value: _effectiveFrom,
                  onChanged: (date) => setState(() => _effectiveFrom = date),
                ),
                _field(
                  width: 320,
                  controller: _address1,
                  label: 'Address line 1',
                ),
                _field(
                  width: 320,
                  controller: _address2,
                  label: 'Address line 2',
                ),
                _field(width: 210, controller: _city, label: 'City'),
                _field(width: 210, controller: _postal, label: 'Postal code'),
                _field(
                  width: 210,
                  controller: _provider,
                  label: 'Provider key (future)',
                ),
                SizedBox(
                  width: 640,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: [
                      FilterChip(
                        selected: _einvoice,
                        label: const Text('E-Invoice config'),
                        onSelected: (value) =>
                            setState(() => _einvoice = value),
                      ),
                      FilterChip(
                        selected: _ewaybill,
                        label: const Text('E-Way Bill config'),
                        onSelected: (value) =>
                            setState(() => _ewaybill = value),
                      ),
                      FilterChip(
                        selected: _returns,
                        label: const Text('GST Returns'),
                        onSelected: (value) => setState(() => _returns = value),
                      ),
                      FilterChip(
                        selected: _active,
                        label: const Text('Active'),
                        onSelected: (value) => setState(() => _active = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 640,
                  child: Text(
                    'Provider toggles are configuration only. '
                    'They do not enable GSP/IRP submission.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Widget _field({
    required double width,
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        validator: validator,
        textCapitalization: capitalization,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _RegistrationFormValue(
        id: _emptyToNull(
          _firstText(widget.existing ?? const <String, dynamic>{}, [
            'id',
            'registration_id',
          ]),
        ),
        gstin: _gstin.text.trim(),
        legalName: _legal.text.trim(),
        tradeName: _emptyToNull(_trade.text),
        registrationType: _type,
        stateCode: _state.text.trim(),
        addressLine1: _emptyToNull(_address1.text),
        addressLine2: _emptyToNull(_address2.text),
        city: _emptyToNull(_city.text),
        postalCode: _emptyToNull(_postal.text),
        einvoiceEnabled: _einvoice,
        ewaybillEnabled: _ewaybill,
        returnsEnabled: _returns,
        providerKey: _emptyToNull(_provider.text),
        active: _active,
        effectiveFrom: _effectiveFrom,
      ),
    );
  }
}

class _RegistrationFormValue {
  const _RegistrationFormValue({
    required this.id,
    required this.gstin,
    required this.legalName,
    required this.tradeName,
    required this.registrationType,
    required this.stateCode,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.postalCode,
    required this.einvoiceEnabled,
    required this.ewaybillEnabled,
    required this.returnsEnabled,
    required this.providerKey,
    required this.active,
    required this.effectiveFrom,
  });

  final String? id;
  final String gstin;
  final String legalName;
  final String? tradeName;
  final String registrationType;
  final String stateCode;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postalCode;
  final bool einvoiceEnabled;
  final bool ewaybillEnabled;
  final bool returnsEnabled;
  final String? providerKey;
  final bool active;
  final DateTime effectiveFrom;
}

class _LocationMappingDialog extends StatefulWidget {
  const _LocationMappingDialog({
    required this.locations,
    required this.registrations,
  });

  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> registrations;

  @override
  State<_LocationMappingDialog> createState() => _LocationMappingDialogState();
}

class _LocationMappingDialogState extends State<_LocationMappingDialog> {
  String? _locationId;
  String? _registrationId;
  DateTime _effectiveFrom = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Map location to GST registration'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _locationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Business location',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final row in widget.locations)
                  DropdownMenuItem(
                    value: _s(row['id']),
                    child: Text(_s(row['name'])),
                  ),
              ],
              onChanged: (value) => setState(() => _locationId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _registrationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'GST registration',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final row in widget.registrations)
                  DropdownMenuItem(
                    value: _firstText(row, ['id', 'registration_id']),
                    child: Text(
                      '${_s(row['gstin'])} â€¢ '
                      '${_firstText(row, ['legal_name', 'trade_name'])}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _registrationId = value),
            ),
            const SizedBox(height: 10),
            _DateField(
              width: 520,
              label: 'Effective from',
              value: _effectiveFrom,
              onChanged: (date) => setState(() => _effectiveFrom = date),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _locationId == null || _registrationId == null
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _LocationMappingValue(
                      locationId: _locationId!,
                      registrationId: _registrationId!,
                      effectiveFrom: _effectiveFrom,
                    ),
                  );
                },
          child: const Text('Map'),
        ),
      ],
    );
  }
}

class _LocationMappingValue {
  const _LocationMappingValue({
    required this.locationId,
    required this.registrationId,
    required this.effectiveFrom,
  });

  final String locationId;
  final String registrationId;
  final DateTime effectiveFrom;
}

// =============================================================================
// PRODUCT GST CARD / FORM
// =============================================================================

class _ProductProfileCard extends StatelessWidget {
  const _ProductProfileCard({required this.row, this.onEdit});

  final Map<String, dynamic> row;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final name = _firstText(row, [
      'product_name',
      'name',
      'variant_name',
    ], fallback: 'Product');
    final variant = _firstText(row, ['variant_name'], fallback: '');

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: 0.15,
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                variant.isEmpty ? name : '$name â€¢ $variant',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusPill(
              label: _firstText(row, [
                'validation_status',
              ], fallback: 'configured'),
              tone: _validationTone(row['validation_status']),
            ),
          ],
        ),
        subtitle: Text(
          [
            'HSN/SAC ${_firstText(row, ['hsn_sac'], fallback: 'â€”')}',
            '${_number(row['gst_rate']).toStringAsFixed(2)}% GST',
            _labelize(_firstText(row, ['taxability'], fallback: 'taxable')),
            _truthy(row['tax_inclusive']) ? 'Inclusive' : 'Exclusive',
            _truthy(row['reverse_charge']) ? 'RCM' : '',
          ].where((e) => e.isNotEmpty).join('  â€¢  '),
        ),
        trailing: IconButton(
          tooltip: 'Edit GST profile',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
      ),
    );
  }
}

class _ProductGstDialog extends StatefulWidget {
  const _ProductGstDialog({
    required this.existing,
    required this.selectedProduct,
    required this.rates,
  });

  final Map<String, dynamic>? existing;
  final Map<String, dynamic>? selectedProduct;
  final List<Map<String, dynamic>> rates;

  @override
  State<_ProductGstDialog> createState() => _ProductGstDialogState();
}

class _ProductGstDialogState extends State<_ProductGstDialog> {
  final _formKey = GlobalKey<FormState>();

  late final String _variantId;
  late final String _productLabel;
  late final TextEditingController _hsn;
  late final TextEditingController _gstRate;
  late final TextEditingController _cessRate;
  late final TextEditingController _cessPerUnit;
  late final TextEditingController _notes;

  String _supplyKind = 'goods';
  String _taxability = 'taxable';
  bool _taxInclusive = false;
  bool _reverseCharge = false;
  DateTime _effectiveFrom = DateTime.now();

  static const _taxabilityValues = [
    'taxable',
    'exempt',
    'nil_rated',
    'non_gst',
  ];

  @override
  void initState() {
    super.initState();
    final row =
        widget.existing ?? widget.selectedProduct ?? const <String, dynamic>{};

    _variantId = _firstText(row, ['variant_id']);
    _productLabel = [
      _firstText(row, ['product_name', 'name'], fallback: 'Product'),
      _firstText(row, ['variant_name'], fallback: ''),
    ].where((e) => e.isNotEmpty).join(' â€¢ ');

    _supplyKind = ['goods', 'service'].contains(row['supply_kind'])
        ? row['supply_kind'].toString()
        : (_s(row['item_type']).toLowerCase() == 'service'
              ? 'service'
              : 'goods');
    _taxability = _taxabilityValues.contains(row['taxability'])
        ? row['taxability'].toString()
        : 'taxable';

    _hsn = TextEditingController(text: _s(row['hsn_sac'], fallback: ''));
    _gstRate = TextEditingController(text: _number(row['gst_rate']).toString());
    _cessRate = TextEditingController(
      text: _number(row['cess_rate']).toString(),
    );
    _cessPerUnit = TextEditingController(
      text: _number(row['cess_per_unit']).toString(),
    );
    _notes = TextEditingController(text: _s(row['notes'], fallback: ''));

    _taxInclusive = _truthy(row['tax_inclusive']);
    _reverseCharge = _truthy(row['reverse_charge']);
    _effectiveFrom = _tryDate(row['effective_from']) ?? DateTime.now();
  }

  @override
  void dispose() {
    _hsn.dispose();
    _gstRate.dispose();
    _cessRate.dispose();
    _cessPerUnit.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Product GST profile'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 640,
                  child: Text(
                    _productLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _supplyKind,
                    decoration: const InputDecoration(
                      labelText: 'Supply kind',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'goods', child: Text('Goods')),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Service'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _supplyKind = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _taxability,
                    decoration: const InputDecoration(
                      labelText: 'Taxability',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final value in _taxabilityValues)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_labelize(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _taxability = value;
                        if (value != 'taxable') {
                          _gstRate.text = '0';
                          _cessRate.text = '0';
                          _cessPerUnit.text = '0';
                          _taxInclusive = false;
                        }
                      });
                    },
                  ),
                ),
                _smallField(
                  controller: _hsn,
                  label: 'HSN / SAC',
                  validator: (value) {
                    final text = value?.replaceAll(RegExp(r'\s+'), '') ?? '';
                    if (_taxability == 'taxable' && text.isEmpty) {
                      return 'Required';
                    }
                    if (text.isNotEmpty &&
                        !RegExp(r'^\d{4}(\d{2})?(\d{2})?$').hasMatch(text)) {
                      return 'Use 4, 6 or 8 digits';
                    }
                    return null;
                  },
                ),
                _smallField(
                  controller: _gstRate,
                  label: 'GST rate %',
                  numeric: true,
                  enabled: _taxability == 'taxable',
                  validator: _nonNegative,
                ),
                _smallField(
                  controller: _cessRate,
                  label: 'Cess rate %',
                  numeric: true,
                  enabled: _taxability == 'taxable',
                  validator: _nonNegative,
                ),
                _smallField(
                  controller: _cessPerUnit,
                  label: 'Cess / unit',
                  numeric: true,
                  enabled: _taxability == 'taxable',
                  validator: _nonNegative,
                ),
                _DateField(
                  width: 210,
                  label: 'Effective from',
                  value: _effectiveFrom,
                  onChanged: (date) => setState(() => _effectiveFrom = date),
                ),
                SizedBox(
                  width: 640,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        selected: _taxInclusive,
                        label: const Text('Tax inclusive'),
                        onSelected: _taxability == 'taxable'
                            ? (value) => setState(() => _taxInclusive = value)
                            : null,
                      ),
                      FilterChip(
                        selected: _reverseCharge,
                        label: const Text('Reverse charge'),
                        onSelected: (value) =>
                            setState(() => _reverseCharge = value),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 640,
                  child: TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 640,
                  child: Text(
                    'GST is not calculated here. The saved profile is an '
                    'input to the server-authoritative GST engine.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Widget _smallField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool numeric = false,
    bool enabled = true,
  }) {
    return SizedBox(
      width: 200,
      child: TextFormField(
        controller: controller,
        validator: validator,
        enabled: enabled,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  String? _nonNegative(String? value) {
    final number = num.tryParse(value?.trim() ?? '');
    if (number == null || number < 0) return '0 or more';
    return null;
  }

  void _submit() {
    if (_variantId.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;

    final gstRate = num.parse(_gstRate.text.trim());
    final cessRate = num.parse(_cessRate.text.trim());
    final cessPerUnit = num.parse(_cessPerUnit.text.trim());

    if (_taxability != 'taxable' &&
        (gstRate != 0 || cessRate != 0 || cessPerUnit != 0)) {
      return;
    }

    Navigator.pop(
      context,
      _ProductGstFormValue(
        variantId: _variantId,
        supplyKind: _supplyKind,
        hsnSac: _hsn.text.trim(),
        taxability: _taxability,
        gstRate: gstRate,
        cessRate: cessRate,
        cessPerUnit: cessPerUnit,
        taxInclusive: _taxInclusive,
        reverseCharge: _reverseCharge,
        notes: _emptyToNull(_notes.text),
        effectiveFrom: _effectiveFrom,
      ),
    );
  }
}

class _ProductGstFormValue {
  const _ProductGstFormValue({
    required this.variantId,
    required this.supplyKind,
    required this.hsnSac,
    required this.taxability,
    required this.gstRate,
    required this.cessRate,
    required this.cessPerUnit,
    required this.taxInclusive,
    required this.reverseCharge,
    required this.notes,
    required this.effectiveFrom,
  });

  final String variantId;
  final String supplyKind;
  final String hsnSac;
  final String taxability;
  final num gstRate;
  final num cessRate;
  final num cessPerUnit;
  final bool taxInclusive;
  final bool reverseCharge;
  final String? notes;
  final DateTime effectiveFrom;
}

// =============================================================================
// PARTY GST CARD / FORM
// =============================================================================

class _PartyProfileCard extends StatelessWidget {
  const _PartyProfileCard({required this.row, this.onEdit});

  final Map<String, dynamic> row;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final name = _firstText(row, [
      'party_name',
      'legal_name',
      'trade_name',
    ], fallback: 'Party');

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: 0.15,
      child: ListTile(
        dense: true,
        leading: Icon(
          _s(row['party_type']).toLowerCase() == 'supplier'
              ? Icons.local_shipping_outlined
              : Icons.person_outline,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusPill(
              label: _firstText(row, [
                'validation_status',
              ], fallback: 'configured'),
              tone: _validationTone(row['validation_status']),
            ),
          ],
        ),
        subtitle: Text(
          [
            _labelize(
              _firstText(row, ['registration_type'], fallback: 'unregistered'),
            ),
            _firstText(row, ['gstin'], fallback: ''),
            _firstText(row, ['state_code'], fallback: ''),
            _firstText(row, ['place_of_supply_code'], fallback: ''),
          ].where((e) => e.isNotEmpty).join('  â€¢  '),
        ),
        trailing: IconButton(
          tooltip: 'Edit GST profile',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
      ),
    );
  }
}

class _PartyGstDialog extends StatefulWidget {
  const _PartyGstDialog({
    required this.existing,
    required this.selectedParty,
    required this.states,
  });

  final Map<String, dynamic>? existing;
  final Map<String, dynamic>? selectedParty;
  final List<Map<String, dynamic>> states;

  @override
  State<_PartyGstDialog> createState() => _PartyGstDialogState();
}

class _PartyGstDialogState extends State<_PartyGstDialog> {
  final _formKey = GlobalKey<FormState>();

  late final String _partyId;
  late final String _partyName;
  late String _partyType;

  late final TextEditingController _gstin;
  late final TextEditingController _legal;
  late final TextEditingController _trade;
  late final TextEditingController _state;
  late final TextEditingController _pos;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _postal;
  late final TextEditingController _country;

  String _registrationType = 'unregistered';
  bool _active = true;

  static const _registrationTypes = [
    'registered',
    'unregistered',
    'composition',
    'sez',
    'export',
    'exempt',
  ];

  bool get _gstinRequired =>
      {'registered', 'composition', 'sez'}.contains(_registrationType);

  bool get _gstinForbidden =>
      {'unregistered', 'export', 'exempt'}.contains(_registrationType);

  @override
  void initState() {
    super.initState();
    final row =
        widget.existing ?? widget.selectedParty ?? const <String, dynamic>{};

    _partyId = _firstText(row, ['party_id']);
    _partyName = _firstText(row, ['party_name', 'name'], fallback: 'Party');
    _partyType = _firstText(row, ['party_type'], fallback: 'customer');

    final regType = _firstText(row, [
      'registration_type',
    ], fallback: 'unregistered');
    _registrationType = _registrationTypes.contains(regType)
        ? regType
        : 'unregistered';

    _gstin = TextEditingController(text: _s(row['gstin'], fallback: ''));
    _legal = TextEditingController(text: _s(row['legal_name'], fallback: ''));
    _trade = TextEditingController(text: _s(row['trade_name'], fallback: ''));
    _state = TextEditingController(text: _s(row['state_code'], fallback: ''));
    _pos = TextEditingController(
      text: _s(row['place_of_supply_code'], fallback: ''),
    );
    _address1 = TextEditingController(
      text: _s(row['address_line1'], fallback: ''),
    );
    _address2 = TextEditingController(
      text: _s(row['address_line2'], fallback: ''),
    );
    _city = TextEditingController(text: _s(row['city'], fallback: ''));
    _postal = TextEditingController(text: _s(row['postal_code'], fallback: ''));
    _country = TextEditingController(text: _s(row['country'], fallback: 'IN'));
    _active = row['active'] != false;
  }

  @override
  void dispose() {
    for (final controller in [
      _gstin,
      _legal,
      _trade,
      _state,
      _pos,
      _address1,
      _address2,
      _city,
      _postal,
      _country,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Party GST profile'),
      content: SizedBox(
        width: 690,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 650,
                  child: Text(
                    '${_labelize(_partyType)} â€¢ $_partyName',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: _registrationType,
                    decoration: const InputDecoration(
                      labelText: 'Registration type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final value in _registrationTypes)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_labelize(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _registrationType = value;
                        if (_gstinForbidden) _gstin.clear();
                      });
                    },
                  ),
                ),
                _field(
                  width: 300,
                  controller: _gstin,
                  label: 'GSTIN',
                  capitalization: TextCapitalization.characters,
                  enabled: !_gstinForbidden,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (_gstinRequired && text.isEmpty) return 'Required';
                    if (_gstinForbidden && text.isNotEmpty) {
                      return 'Not allowed for this type';
                    }
                    return null;
                  },
                ),
                _field(width: 320, controller: _legal, label: 'Legal name'),
                _field(width: 320, controller: _trade, label: 'Trade name'),
                _field(width: 200, controller: _state, label: 'State code'),
                _field(width: 200, controller: _pos, label: 'Place of supply'),
                _field(
                  width: 320,
                  controller: _address1,
                  label: 'Address line 1',
                ),
                _field(
                  width: 320,
                  controller: _address2,
                  label: 'Address line 2',
                ),
                _field(width: 210, controller: _city, label: 'City'),
                _field(width: 210, controller: _postal, label: 'Postal code'),
                _field(width: 150, controller: _country, label: 'Country'),
                SizedBox(
                  width: 650,
                  child: FilterChip(
                    selected: _active,
                    label: const Text('Active'),
                    onSelected: (value) => setState(() => _active = value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Widget _field({
    required double width,
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool enabled = true,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        validator: validator,
        enabled: enabled,
        textCapitalization: capitalization,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _submit() {
    if (_partyId.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _PartyGstFormValue(
        id: _emptyToNull(
          _firstText(widget.existing ?? const <String, dynamic>{}, [
            'id',
            'profile_id',
          ]),
        ),
        partyType: _partyType,
        partyId: _partyId,
        registrationType: _registrationType,
        gstin: _gstinForbidden ? null : _emptyToNull(_gstin.text),
        legalName: _emptyToNull(_legal.text),
        tradeName: _emptyToNull(_trade.text),
        stateCode: _emptyToNull(_state.text),
        placeOfSupplyCode: _emptyToNull(_pos.text),
        addressLine1: _emptyToNull(_address1.text),
        addressLine2: _emptyToNull(_address2.text),
        city: _emptyToNull(_city.text),
        postalCode: _emptyToNull(_postal.text),
        country: _country.text.trim().isEmpty ? 'IN' : _country.text.trim(),
        active: _active,
      ),
    );
  }
}

class _PartyGstFormValue {
  const _PartyGstFormValue({
    required this.id,
    required this.partyType,
    required this.partyId,
    required this.registrationType,
    required this.gstin,
    required this.legalName,
    required this.tradeName,
    required this.stateCode,
    required this.placeOfSupplyCode,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.active,
  });

  final String? id;
  final String partyType;
  final String partyId;
  final String registrationType;
  final String? gstin;
  final String? legalName;
  final String? tradeName;
  final String? stateCode;
  final String? placeOfSupplyCode;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postalCode;
  final String country;
  final bool active;
}

// =============================================================================
// LOOKUP DIALOG
// =============================================================================

class _LookupDialog extends StatefulWidget {
  const _LookupDialog({
    required this.title,
    required this.initialRows,
    required this.load,
    required this.itemBuilder,
  });

  final String title;
  final List<Map<String, dynamic>> initialRows;
  final Future<List<Map<String, dynamic>>> Function(String query) load;
  final Widget Function(Map<String, dynamic> row) itemBuilder;

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  late List<Map<String, dynamic>> _rows;
  final _search = TextEditingController();
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await widget.load(_search.text.trim());
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 650,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _runSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _runSearch(),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _rows.isEmpty
                  ? const _EmptyState(
                      icon: Icons.search_off,
                      title: 'No results',
                      message: 'Try another search.',
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return InkWell(
                          onTap: () => Navigator.pop(context, row),
                          child: widget.itemBuilder(row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// =============================================================================
// TRANSACTION EVIDENCE
// =============================================================================

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final evidence = _firstText(row, [
      'evidence_status',
      'evidence_type',
      'status',
    ], fallback: 'unknown');
    final authoritative = evidence.toLowerCase().contains('authoritative');

    final number = _firstText(row, [
      'document_number',
      'source_number',
      'invoice_number',
      'number',
    ], fallback: 'Document');
    final type = _firstText(row, [
      'source_type',
      'document_type',
    ], fallback: '');
    final date = _firstText(row, [
      'document_date',
      'source_date',
      'date',
    ], fallback: '');

    final taxable = _firstNumber(row, [
      'taxable_value',
      'taxable_total',
      'subtotal',
    ]);
    final tax = _firstNumber(row, [
      'tax_total',
      'gst_total',
      'collected_tax_total',
    ]);
    final total = _firstNumber(row, ['grand_total', 'total']);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0.12,
      child: ListTile(
        dense: true,
        onTap: onOpen,
        leading: Icon(
          authoritative ? Icons.verified_outlined : Icons.history_outlined,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusPill(
              label: authoritative ? 'Authoritative' : 'Legacy unverified',
              tone: authoritative ? _PillTone.success : _PillTone.warning,
            ),
          ],
        ),
        subtitle: Text(
          [
            _labelize(type),
            date,
            'Taxable ${taxable.toStringAsFixed(2)}',
            'GST ${tax.toStringAsFixed(2)}',
            'Total ${total.toStringAsFixed(2)}',
          ].where((e) => e.isNotEmpty).join('  â€¢  '),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _EvidenceDialog extends StatelessWidget {
  const _EvidenceDialog({required this.data});

  final Map<String, dynamic> data;

  Map<String, dynamic> _eMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _eRows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  String _eText(
    Map<String, dynamic> source,
    List<String> keys, {
    String fallback = 'â€”',
  }) {
    for (final key in keys) {
      final value = source[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  double _eNum(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => 'â‚¹${value.toStringAsFixed(2)}';

  String _qty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(3);
  }

  String _nice(String value) {
    if (value.trim().isEmpty || value == 'â€”') return 'â€”';
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _dateLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value.isEmpty ? 'â€”' : value;
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${parsed.day.toString().padLeft(2, '0')} '
        '${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    String value, {
    bool mono = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 175, maxWidth: 285),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              value,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    double value, {
    bool emphasize = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: emphasize
              ? scheme.primaryContainer.withValues(alpha: .48)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _money(value),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotSummary(BuildContext context, Map<String, dynamic> snapshot) {
    final interstate = snapshot['interstate'] == true;
    final hashValid = snapshot['hash_valid'] == true;
    final taxMode = _eText(snapshot, ['tax_mode']);
    final sourceNumber = _eText(snapshot, ['document_number', 'source_number']);
    final documentKind = _nice(_eText(snapshot, ['document_kind']));
    final documentClass = _nice(_eText(snapshot, ['document_class']));
    final supplyType = _nice(_eText(snapshot, ['supply_type']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          'Document',
          Icons.receipt_long_outlined,
          subtitle:
              'Immutable GST identity captured when this document posted.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _field(context, 'Document No.', sourceNumber),
            _field(
              context,
              'Document Date',
              _dateLabel(_eText(snapshot, ['document_date'], fallback: '')),
            ),
            _field(context, 'Tax Mode', _nice(taxMode)),
            _field(
              context,
              'Supply',
              interstate ? 'Inter-state' : 'Intra-state',
            ),
            _field(context, 'Document Type', documentKind),
            _field(context, 'Document Class', documentClass),
            _field(context, 'Supply Type', supplyType),
            _field(
              context,
              'Place of Supply',
              _eText(snapshot, ['place_of_supply_code']),
            ),
            _field(
              context,
              'Supplier GSTIN',
              _eText(snapshot, ['supplier_gstin']),
              mono: true,
            ),
            _field(
              context,
              'Recipient GSTIN',
              _eText(snapshot, ['recipient_gstin']),
              mono: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          'Tax Summary',
          Icons.account_balance_outlined,
          subtitle: 'Server-authoritative GST components for this document.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 168,
              child: _metric(
                context,
                'Taxable Value',
                _eNum(snapshot, 'taxable_total'),
              ),
            ),
            SizedBox(
              width: 148,
              child: _metric(context, 'CGST', _eNum(snapshot, 'cgst_total')),
            ),
            SizedBox(
              width: 148,
              child: _metric(context, 'SGST', _eNum(snapshot, 'sgst_total')),
            ),
            if (_eNum(snapshot, 'utgst_total').abs() > 0.000001)
              SizedBox(
                width: 148,
                child: _metric(
                  context,
                  'UTGST',
                  _eNum(snapshot, 'utgst_total'),
                ),
              ),
            SizedBox(
              width: 148,
              child: _metric(context, 'IGST', _eNum(snapshot, 'igst_total')),
            ),
            SizedBox(
              width: 148,
              child: _metric(context, 'Cess', _eNum(snapshot, 'cess_total')),
            ),
            SizedBox(
              width: 172,
              child: _metric(
                context,
                'GST Collected',
                _eNum(snapshot, 'tax_collected_total'),
              ),
            ),
            SizedBox(
              width: 180,
              child: _metric(
                context,
                'Grand Total',
                _eNum(snapshot, 'grand_total'),
                emphasize: true,
              ),
            ),
          ],
        ),
        if (_eNum(snapshot, 'rcm_tax_payable_total').abs() > 0.000001) ...[
          const SizedBox(height: 8),
          _NoticeCard(
            icon: Icons.swap_horiz_outlined,
            title: 'Reverse charge applies',
            message:
                'RCM tax payable: ${_money(_eNum(snapshot, 'rcm_tax_payable_total'))}',
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              hashValid
                  ? Icons.verified_outlined
                  : Icons.warning_amber_outlined,
              size: 18,
              color: hashValid
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                hashValid
                    ? 'Snapshot integrity verified â€¢ ${_eText(snapshot, ['engine_version'], fallback: 'GST v5.2 engine')}'
                    : 'Snapshot integrity check failed. Review this evidence before relying on it.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: hashValid
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineTable(BuildContext context, List<Map<String, dynamic>> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          'GST Line Breakdown',
          Icons.format_list_bulleted_outlined,
          subtitle:
              '${lines.length} immutable tax line${lines.length == 1 ? '' : 's'}.',
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 58,
              columnSpacing: 20,
              headingTextStyle: headerStyle,
              columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('HSN/SAC')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Taxable'), numeric: true),
                DataColumn(label: Text('GST %'), numeric: true),
                DataColumn(label: Text('CGST'), numeric: true),
                DataColumn(label: Text('SGST/UTGST'), numeric: true),
                DataColumn(label: Text('IGST'), numeric: true),
                DataColumn(label: Text('Cess'), numeric: true),
                DataColumn(label: Text('Total'), numeric: true),
              ],
              rows: [
                for (final line in lines)
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _eText(line, [
                                  'product_name',
                                  'variant_name',
                                  'sku',
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _eText(line, ['sku'], fallback: ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(_eText(line, ['hsn_sac']))),
                      DataCell(Text(_qty(_eNum(line, 'quantity')))),
                      DataCell(Text(_money(_eNum(line, 'taxable_value')))),
                      DataCell(
                        Text(
                          '${_eNum(line, 'applied_gst_rate').toStringAsFixed(2)}%',
                        ),
                      ),
                      DataCell(Text(_money(_eNum(line, 'cgst')))),
                      DataCell(
                        Text(
                          _money(_eNum(line, 'sgst') + _eNum(line, 'utgst')),
                        ),
                      ),
                      DataCell(Text(_money(_eNum(line, 'igst')))),
                      DataCell(Text(_money(_eNum(line, 'cess')))),
                      DataCell(Text(_money(_eNum(line, 'line_total')))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _journalSection(BuildContext context, Map<String, dynamic> journal) {
    final entry = _eMap(journal['entry']);
    final lines = _eRows(journal['lines']);
    if (entry.isEmpty && lines.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          'Accounting',
          Icons.menu_book_outlined,
          subtitle: 'Posted journal linked to this GST document.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _field(context, 'Journal No.', _eText(entry, ['entry_number'])),
            _field(
              context,
              'Journal Date',
              _dateLabel(_eText(entry, ['entry_date'], fallback: '')),
            ),
            _field(
              context,
              'Status',
              _nice(_eText(entry, ['status'], fallback: 'posted')),
            ),
            _field(context, 'Reference', _eText(entry, ['source_reference'])),
          ],
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          const Text('No accounting lines were returned.')
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 52,
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                ],
                rows: [
                  for (final line in lines)
                    DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 210,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _eText(line, ['account_name', 'system_key']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _eText(line, ['account_code'], fallback: ''),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 250,
                            child: Text(
                              _eText(line, ['description']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(_money(_eNum(line, 'debit')))),
                        DataCell(Text(_money(_eNum(line, 'credit')))),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _technicalDetails(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pretty = const JsonEncoder.withIndent('  ').convert(data);

    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.code_outlined, size: 19),
        title: const Text(
          'Technical details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Raw IDs, hashes and complete server evidence for troubleshooting.',
        ),
        children: [
          const Divider(height: 1),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 330),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.42,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final evidence = _eText(data, [
      'evidence_status',
      'evidence_type',
      'status',
    ], fallback: 'unknown');
    final authoritative = evidence.toLowerCase().contains('authoritative');

    final snapshot = _eMap(data['snapshot']);
    final legacy = _eMap(data['legacy']);
    final journal = _eMap(data['journal']);
    final snapshotLines = _eRows(snapshot['lines']);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      title: Row(
        children: [
          Icon(
            authoritative ? Icons.verified_outlined : Icons.history_outlined,
            size: 24,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'GST Evidence',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusPill(
            label: authoritative ? 'Authoritative' : 'Legacy unverified',
            tone: authoritative ? _PillTone.success : _PillTone.warning,
          ),
        ],
      ),
      content: SizedBox(
        width: 960,
        height: MediaQuery.sizeOf(context).height * .72,
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!authoritative) ...[
                  const _NoticeCard(
                    icon: Icons.history_outlined,
                    title: 'Legacy evidence is read-only',
                    message:
                        'This transaction was created through a v5.1 path. '
                        'THQ does not silently upgrade or rewrite it as '
                        'authoritative GST evidence.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (authoritative && snapshot.isNotEmpty) ...[
                  _snapshotSummary(context, snapshot),
                  _lineTable(context, snapshotLines),
                ] else if (legacy.isNotEmpty) ...[
                  _sectionHeader(
                    context,
                    'Legacy Evidence',
                    Icons.history_outlined,
                    subtitle:
                        'Historical marker retained exactly as recorded by the legacy path.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _field(
                        context,
                        'Document No.',
                        _eText(legacy, [
                          'document_number',
                          'source_number',
                          'source_reference',
                        ]),
                      ),
                      _field(
                        context,
                        'Source Type',
                        _nice(_eText(legacy, ['source_type'])),
                      ),
                      _field(
                        context,
                        'Created',
                        _dateLabel(
                          _eText(legacy, ['created_at'], fallback: ''),
                        ),
                      ),
                    ],
                  ),
                ] else
                  const _NoticeCard(
                    icon: Icons.warning_amber_outlined,
                    title: 'GST evidence unavailable',
                    message:
                        'THQ did not receive a snapshot or legacy evidence object '
                        'for this transaction.',
                  ),
                _journalSection(context, journal),
                _technicalDetails(context),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 17),
          label: const Text('Close'),
        ),
      ],
    );
  }
}

// =============================================================================
// DETAIL / ERROR DIALOGS
// =============================================================================

class _JsonDetailDialog extends StatelessWidget {
  const _JsonDetailDialog({required this.title, required this.data});

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 760,
        height: 600,
        child: SingleChildScrollView(child: _JsonSections(data: data)),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onClose});

  final Object error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error.toString(),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'GST & Compliance could not be opened',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DATE FIELD
// =============================================================================

class _DateField extends StatelessWidget {
  const _DateField({
    required this.width,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final double width;
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            firstDate: DateTime(2017, 7, 1),
            lastDate: DateTime.now().add(const Duration(days: 3650)),
            initialDate: value,
          );
          if (date != null) onChanged(date);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 17),
          ),
          child: Text(_date(value)),
        ),
      ),
    );
  }
}

// =============================================================================
// PURE UI HELPERS
// =============================================================================

IconData _tabIcon(String key) {
  return switch (key) {
    'overview' => Icons.dashboard_outlined,
    'registrations' => Icons.badge_outlined,
    'products' => Icons.inventory_2_outlined,
    'parties' => Icons.people_outline,
    'transactions' => Icons.receipt_long_outlined,
    'tax_summary' => Icons.summarize_outlined,
    'accounting' => Icons.account_balance_outlined,
    'returns' => Icons.assignment_turned_in_outlined,
    'einvoice' => Icons.qr_code_2_outlined,
    'ewaybill' => Icons.local_shipping_outlined,
    _ => Icons.circle_outlined,
  };
}

_PillTone _validationTone(dynamic value) {
  final status = _s(value, fallback: '').toLowerCase();
  if (status.contains('validated')) return _PillTone.success;
  if (status.contains('fail')) return _PillTone.error;
  if (status.contains('stale')) return _PillTone.warning;
  return _PillTone.neutral;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];

  return value
      .map<Map<String, dynamic>>((entry) {
        if (entry is Map<String, dynamic>) {
          return Map<String, dynamic>.from(entry);
        }
        if (entry is Map) {
          return entry.map((key, value) => MapEntry(key.toString(), value));
        }
        return <String, dynamic>{'value': entry};
      })
      .toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((entry) => entry?.toString() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String _s(dynamic value, {String fallback = 'â€”'}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String _firstText(
  Map<String, dynamic> row,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = row[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

num _firstNumber(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    if (row[key] != null) return _number(row[key]);
  }
  return 0;
}

int _integer(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().toLowerCase() ?? '';
  return text == 'true' || text == 't' || text == '1' || text == 'yes';
}

String _labelize(String value) {
  if (value.trim().isEmpty) return '';
  final spaced = value.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (spaced.isEmpty) return '';
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _display(dynamic value) {
  if (value == null) return 'â€”';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value.toString();
  if (value is Map || value is List) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  final text = value.toString().trim();
  return text.isEmpty ? 'â€”' : text;
}

String _date(DateTime value) {
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d/$m/${value.year}';
}

DateTime? _tryDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String? _emptyToNull(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

dynamic _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}
