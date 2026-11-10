import 'dart:async';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';

/// Reusable searchable autocomplete selector for Drivers.
class SearchableDriverSelector extends StatefulWidget {
  final ClientSession session;
  final String? initialDriverId;
  final String? initialDriverName;
  final ValueChanged<Map<String, dynamic>?> onDriverSelected;
  final String labelText;
  final bool isRequired;

  const SearchableDriverSelector({
    super.key,
    required this.session,
    this.initialDriverId,
    this.initialDriverName,
    required this.onDriverSelected,
    this.labelText = 'Driver',
    this.isRequired = false,
  });

  @override
  State<SearchableDriverSelector> createState() =>
      _SearchableDriverSelectorState();
}

class _SearchableDriverSelectorState extends State<SearchableDriverSelector> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  Map<String, dynamic>? _selectedDriver;

  @override
  void initState() {
    super.initState();
    if (widget.initialDriverName != null &&
        widget.initialDriverName!.isNotEmpty) {
      _controller.text = widget.initialDriverName!;
    }
  }

  @override
  void didUpdateWidget(SearchableDriverSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDriverId != oldWidget.initialDriverId &&
        widget.initialDriverName != null) {
      if (_selectedDriver?['id'] != widget.initialDriverId &&
          _selectedDriver?['driver_id'] != widget.initialDriverId) {
        _controller.text = widget.initialDriverName ?? '';
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _selectedDriver = null;
      });
      widget.onDriverSelected(null);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isLoading = true);
      try {
        final list = await _service.drivers(
          tenantId: widget.session.business.id,
          query: query.trim(),
          limit: 20,
        );
        if (mounted) {
          setState(() {
            _suggestions = list;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _selectDriver(Map<String, dynamic> driver) {
    setState(() {
      _selectedDriver = driver;
      _controller.text = driver['name'] ?? '';
      _suggestions = [];
    });
    _focusNode.unfocus();
    widget.onDriverSelected(driver);
  }

  void _clearSelection() {
    setState(() {
      _selectedDriver = null;
      _controller.clear();
      _suggestions = [];
    });
    widget.onDriverSelected(null);
  }

  Future<void> _quickCreateDriver() async {
    final nameCtrl = TextEditingController(text: _controller.text.trim());
    final phoneCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final wageCtrl = TextEditingController();
    var saving = false;

    final created = await showThqDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Driver'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Driver name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Driver code / ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: licenseCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'License number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: wageCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Default wage',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Driver name is required.')),
                        );
                        return;
                      }
                      setDlgState(() => saving = true);
                      try {
                        final res = await _service.saveDriver(
                          tenantId: widget.session.business.id,
                          driver: {
                            'name': name,
                            'phone': phoneCtrl.text.trim(),
                            'driver_code': codeCtrl.text.trim(),
                            'license_number': licenseCtrl.text.trim(),
                            'default_wage': double.tryParse(wageCtrl.text.trim()) ?? 0,
                            'active': true,
                          },
                        );
                        final driverId = res['driver_id']?.toString();
                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop({
                            'id': driverId,
                            'driver_id': driverId,
                            'name': name,
                            'phone': phoneCtrl.text.trim(),
                            'license_number': licenseCtrl.text.trim(),
                            'driver_code': codeCtrl.text.trim(),
                          });
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDlgState(() => saving = false);
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text(err.toString())),
                          );
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save Driver'),
            ),
          ],
        ),
      ),
    );

    if (created != null && mounted) {
      _selectDriver(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: '${widget.labelText}${widget.isRequired ? ' *' : ''}',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clearSelection,
                    tooltip: 'Clear driver',
                  ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                  onPressed: _quickCreateDriver,
                  tooltip: 'Add new driver',
                ),
              ],
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final d = _suggestions[index];
                final code = (d['driver_code'] ?? '').toString().trim();
                final phone = (d['phone'] ?? '').toString().trim();
                final license = (d['license_number'] ?? '').toString().trim();

                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, size: 20),
                  title: Text(
                    d['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      if (code.isNotEmpty) 'ID: $code',
                      if (phone.isNotEmpty) phone,
                      if (license.isNotEmpty) 'Lic: $license',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: d['active'] == false
                      ? const Chip(label: Text('Inactive', style: TextStyle(fontSize: 10)))
                      : null,
                  onTap: () => _selectDriver(d),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Reusable searchable autocomplete selector for Trucks / Vehicles.
class SearchableTruckSelector extends StatefulWidget {
  final List<Map<String, dynamic>> vehicles;
  final String? initialVehicleId;
  final ValueChanged<Map<String, dynamic>?> onVehicleSelected;
  final ValueChanged<String?>? onSuggestDriver;
  final ValueChanged<Map<String, dynamic>>? onVehicleCreated;
  final ClientSession? session;
  final String? locationId;
  final String labelText;

  const SearchableTruckSelector({
    super.key,
    required this.vehicles,
    this.initialVehicleId,
    required this.onVehicleSelected,
    this.onSuggestDriver,
    this.onVehicleCreated,
    this.session,
    this.locationId,
    this.labelText = 'Truck / Vehicle',
  });

  @override
  State<SearchableTruckSelector> createState() =>
      _SearchableTruckSelectorState();
}

class _SearchableTruckSelectorState extends State<SearchableTruckSelector> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _filtered = [];
  Map<String, dynamic>? _selectedVehicle;
  late List<Map<String, dynamic>> _localVehicles;

  @override
  void initState() {
    super.initState();
    _localVehicles = List<Map<String, dynamic>>.from(widget.vehicles);
    if (widget.initialVehicleId != null) {
      final found = _localVehicles.firstWhere(
        (v) => (v['vehicle_id'] ?? v['id'])?.toString() == widget.initialVehicleId,
        orElse: () => const {},
      );
      if (found.isNotEmpty) {
        _selectedVehicle = found;
        _controller.text = found['registration_number'] ?? '';
      }
    }
  }

  @override
  void didUpdateWidget(SearchableTruckSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vehicles != oldWidget.vehicles) {
      final existingIds = widget.vehicles
          .map((v) => (v['vehicle_id'] ?? v['id'])?.toString())
          .toSet();
      final newLocals = _localVehicles.where(
        (v) => !existingIds.contains((v['vehicle_id'] ?? v['id'])?.toString()),
      );
      _localVehicles = [...widget.vehicles, ...newLocals];
    }
    if (widget.initialVehicleId != oldWidget.initialVehicleId) {
      final found = _localVehicles.firstWhere(
        (v) => (v['vehicle_id'] ?? v['id'])?.toString() == widget.initialVehicleId,
        orElse: () => const {},
      );
      if (found.isNotEmpty &&
          _selectedVehicle?['id'] != widget.initialVehicleId &&
          _selectedVehicle?['vehicle_id'] != widget.initialVehicleId) {
        _selectedVehicle = found;
        _controller.text = found['registration_number'] ?? '';
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filtered = [];
        _selectedVehicle = null;
      });
      widget.onVehicleSelected(null);
      return;
    }

    final normalized = query.replaceAll(' ', '').toUpperCase();
    final results = _localVehicles.where((v) {
      final reg = (v['registration_number'] ?? '').toString().replaceAll(' ', '').toUpperCase();
      final owner = (v['owner_name'] ?? '').toString().toUpperCase();
      final type = (v['vehicle_type'] ?? '').toString().toUpperCase();
      return reg.contains(normalized) || owner.contains(normalized) || type.contains(normalized);
    }).take(15).toList();

    setState(() => _filtered = results);
  }

  void _selectVehicle(Map<String, dynamic> vehicle) {
    setState(() {
      _selectedVehicle = vehicle;
      _controller.text = vehicle['registration_number'] ?? '';
      _filtered = [];
    });
    _focusNode.unfocus();
    widget.onVehicleSelected(vehicle);

    // Suggest default driver if defined on vehicle
    final defaultDriverId = vehicle['default_driver_id']?.toString();
    if (defaultDriverId != null && defaultDriverId.isNotEmpty && widget.onSuggestDriver != null) {
      widget.onSuggestDriver!(defaultDriverId);
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedVehicle = null;
      _controller.clear();
      _filtered = [];
    });
    widget.onVehicleSelected(null);
  }

  Future<void> _quickCreateTruck() async {
    final regCtrl = TextEditingController(text: _controller.text.trim().toUpperCase());
    final makeModelCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final driverNameCtrl = TextEditingController();
    final driverPhoneCtrl = TextEditingController();
    String vehicleType = 'Truck';
    var saving = false;

    final tenantId = widget.session?.business.id;
    final locationId = widget.locationId ??
        (widget.session != null
            ? LocationScopeService.currentForCreate(widget.session!)
            : null);

    final created = await showThqDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_shipping_outlined),
              SizedBox(width: 8),
              Text('Add Truck / Vehicle'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: regCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Registration number *',
                      hintText: 'e.g. KL-10-AZ-1234',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: vehicleType,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle type',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                            DropdownMenuItem(value: 'Tipper', child: Text('Tipper')),
                            DropdownMenuItem(value: 'Taurus', child: Text('Taurus')),
                            DropdownMenuItem(value: 'Trailer', child: Text('Trailer')),
                            DropdownMenuItem(value: 'Pickup', child: Text('Pickup')),
                            DropdownMenuItem(value: 'Dumper', child: Text('Dumper')),
                            DropdownMenuItem(value: 'Lorry', child: Text('Lorry')),
                            DropdownMenuItem(value: 'Other', child: Text('Other')),
                          ],
                          onChanged: (v) => setDlgState(() => vehicleType = v ?? 'Truck'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: capacityCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Nominal Capacity (CFT)',
                            hintText: 'e.g. 150',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: makeModelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Make / model (optional)',
                      hintText: 'e.g. BharatBenz, Tata',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: driverNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Default driver (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: driverPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Driver phone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final reg = regCtrl.text.trim().toUpperCase();
                      if (reg.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Registration number is required.')),
                        );
                        return;
                      }
                      if (tenantId == null || locationId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Active business store/yard is required.')),
                        );
                        return;
                      }

                      setDlgState(() => saving = true);
                      try {
                        final cap = double.tryParse(capacityCtrl.text.trim());
                        final newId = await _service.createVehicle(
                          tenantId: tenantId,
                          locationId: locationId,
                          registrationNumber: reg,
                          vehicleType: vehicleType,
                          makeModel: makeModelCtrl.text.trim().isNotEmpty
                              ? makeModelCtrl.text.trim()
                              : null,
                          driverName: driverNameCtrl.text.trim().isNotEmpty
                              ? driverNameCtrl.text.trim()
                              : null,
                          driverPhone: driverPhoneCtrl.text.trim().isNotEmpty
                              ? driverPhoneCtrl.text.trim()
                              : null,
                          capacityCft: cap,
                        );

                        final newVehicle = {
                          'id': newId,
                          'vehicle_id': newId,
                          'registration_number': reg,
                          'vehicle_type': vehicleType,
                          'make_model': makeModelCtrl.text.trim(),
                          'capacity': cap,
                          'nominal_capacity_cft': cap,
                          'driver_name': driverNameCtrl.text.trim(),
                          'driver_phone': driverPhoneCtrl.text.trim(),
                          'location_id': locationId,
                        };

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(newVehicle);
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDlgState(() => saving = false);
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text(err.toString())),
                          );
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save Truck'),
            ),
          ],
        ),
      ),
    );

    if (created != null && mounted) {
      setState(() {
        _localVehicles.insert(0, created);
      });
      _selectVehicle(created);
      widget.onVehicleCreated?.call(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onSearchChanged,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: 'Search registration or owner',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.local_shipping_outlined),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedVehicle != null || _controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clearSelection,
                    tooltip: 'Clear truck',
                  ),
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 20),
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add_circle,
                            size: 13,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onPressed: _quickCreateTruck,
                  tooltip: 'Add new truck',
                ),
              ],
            ),
          ),
        ),
        if (_filtered.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final v = _filtered[index];
                final reg = v['registration_number'] ?? '';
                final cap = v['nominal_capacity_cft'] ?? v['capacity'];
                final owner = v['owner_name'] ?? v['ownership_type'] ?? '';
                final driver = v['driver_name'] ?? '';

                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_shipping_rounded, size: 20),
                  title: Text(
                    reg,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      if (cap != null) '$cap CFT',
                      if (owner.isNotEmpty) owner,
                      if (driver.isNotEmpty) 'Driver: $driver',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => _selectVehicle(v),
                );
              },
            ),
          ),
      ],
    );
  }
}

