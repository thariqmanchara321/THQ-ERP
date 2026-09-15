import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/logistics_service.dart';
import 'logistics_operations_screen.dart';
import 'logistics_reports_screen.dart';
import 'logistics_receipt_dialog.dart';
import 'vehicle_fleet_screen.dart';
import '../services/stock_transfer_service.dart';
import '../services/transport_service.dart';

class LogisticsScreen extends StatefulWidget {
  final ClientSession session;

  const LogisticsScreen({super.key, required this.session});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  final LogisticsService _logistics = LogisticsService();
  final TransportService _transport = TransportService();
  final StockTransferService _transfers = StockTransferService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  String _view = 'active';
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _approvedTransfers = [];

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  bool get _canCreate =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('transport_service.create') ||
      widget.session.hasPermission('transport_service.manage') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _logistics.list(
          tenantId: _tenantId,
          locationId: _locationId,
          query: _search.text,
        ),
        _transport.vehicles(_tenantId),
        _transfers.list(
          tenantId: _tenantId,
          locationId: _locationId,
          status: 'approved',
        ),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _trips = results[0];
        _vehicles = results[1].where((row) => row['active'] != false).toList();
        _approvedTransfers = results[2];
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _clean(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ThqNotify.showSnackBar(context, SnackBar(content: Text(message)));
  }

  List<Map<String, dynamic>> get _visibleTrips {
    final locationId = _locationId;
    return _trips.where((trip) {
      final status = trip['status']?.toString() ?? '';
      if (_view == 'history') {
        return status == 'closed' || status == 'cancelled';
      }
      if (_view == 'incoming') {
        return locationId != null &&
            trip['to_location_id']?.toString() == locationId &&
            (status == 'in_transit' ||
                status == 'arrived' ||
                status == 'received');
      }
      return status != 'closed' && status != 'cancelled';
    }).toList();
  }

  int _count(String status) =>
      _trips.where((trip) => trip['status']?.toString() == status).length;

  Future<void> _newTrip() async {
    if (!_canCreate) {
      _message('Logistics create permission required.');
      return;
    }
    if (_vehicles.isEmpty) {
      _message(
        'Add an active vehicle from Vehicle Logistics > Vehicles first.',
      );
      return;
    }
    if (_approvedTransfers.isEmpty) {
      _message('There are no approved stock transfers waiting for dispatch.');
      return;
    }

    String vehicleId = _vehicles.first['id'].toString();
    final selectedTransferIds = <String>{};
    String? selectedFrom;
    String? selectedTo;
    final driver = TextEditingController(
      text: _vehicles.first['driver_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: _vehicles.first['driver_phone']?.toString() ?? '',
    );
    final notes = TextEditingController();
    DateTime planned = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final vehicle = _vehicles.firstWhere(
            (row) => row['id'].toString() == vehicleId,
          );
          return AlertDialog(
            title: const Text('New Logistics Trip'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: vehicleId,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        border: OutlineInputBorder(),
                      ),
                      items: _vehicles
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id'].toString(),
                              child: Text(
                                '${row['registration_number'] ?? '-'} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ ${row['vehicle_type'] ?? 'Vehicle'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        final next = _vehicles.firstWhere(
                          (row) => row['id'].toString() == value,
                        );
                        setLocalState(() {
                          vehicleId = value;
                          driver.text = next['driver_name']?.toString() ?? '';
                          phone.text = next['driver_phone']?.toString() ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: driver,
                            decoration: const InputDecoration(
                              labelText: 'Driver',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: phone,
                            decoration: const InputDecoration(
                              labelText: 'Driver phone',
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
                          child: Text(
                            'Planned departure: ${_dateTime(planned)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 1),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              initialDate: planned,
                            );
                            if (picked == null || !context.mounted) {
                              return;
                            }
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(planned),
                            );
                            if (time == null) {
                              return;
                            }
                            setLocalState(() {
                              planned = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                          icon: const Icon(Icons.schedule_outlined),
                          label: const Text('Change'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Approved stock transfers',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'One trip can carry multiple transfers when origin and destination are the same.',
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _approvedTransfers.length,
                        itemBuilder: (context, index) {
                          final transfer = _approvedTransfers[index];
                          final id = transfer['id'].toString();
                          final from = transfer['from_location_id']?.toString();
                          final to = transfer['to_location_id']?.toString();
                          final selected = selectedTransferIds.contains(id);
                          final compatible =
                              selectedTransferIds.isEmpty ||
                              (from == selectedFrom && to == selectedTo);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: compatible || selected
                                ? (value) {
                                    setLocalState(() {
                                      if (value == true) {
                                        if (selectedTransferIds.isEmpty) {
                                          selectedFrom = from;
                                          selectedTo = to;
                                        }
                                        selectedTransferIds.add(id);
                                      } else {
                                        selectedTransferIds.remove(id);
                                        if (selectedTransferIds.isEmpty) {
                                          selectedFrom = null;
                                          selectedTo = null;
                                        }
                                      }
                                    });
                                  }
                                : null,
                            title: Text(
                              '${transfer['transfer_number'] ?? '-'} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ ${transfer['from_location'] ?? '-'} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ ${transfer['to_location'] ?? '-'}',
                            ),
                            subtitle: Text(
                              '${transfer['item_count'] ?? 0} item(s) ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ Qty ${transfer['total_quantity'] ?? 0}',
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Trip notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vehicle default driver: ${vehicle['driver_name'] ?? '-'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: selectedTransferIds.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.route_outlined),
                label: Text('Create Trip (${selectedTransferIds.length})'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final result = await _logistics.create(
          tenantId: _tenantId,
          vehicleId: vehicleId,
          transferIds: selectedTransferIds.toList(),
          plannedDepartureAt: planned,
          driverName: driver.text,
          driverPhone: phone.text,
          notes: notes.text,
        );
        _message('${result['trip_number']} created.');
        await _load();
        if (!mounted) {
          return;
        }
        await _openTrip(result['trip_id'].toString());
      } catch (error) {
        _message(_clean(error));
      }
    }
    driver.dispose();
    phone.dispose();
    notes.dispose();
  }

  Future<void> _openTrip(String tripId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LogisticsTripDialog(
        session: widget.session,
        tripId: tripId,
        onChanged: _load,
      ),
    );
  }

  Widget _summaryCard(String label, int value, IconData icon) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tripCard(Map<String, dynamic> trip) {
    final status = trip['status']?.toString() ?? 'planned';
    return Card(
      child: InkWell(
        onTap: () => _openTrip(trip['id'].toString()),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          trip['trip_number']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            status.replaceAll('_', ' ').toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${trip['from_location'] ?? '-'} -> ${trip['to_location'] ?? '-'}',
                    ),
                    Text(
                      '${trip['vehicle_registration'] ?? '-'} | ${trip['driver_name'] ?? 'No driver'} | ${trip['document_count'] ?? 0} transfer(s)',
                    ),
                    Text(
                      'Qty ${trip['total_quantity'] ?? 0} | In transit ${trip['in_transit_quantity'] ?? 0}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Logistics'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VehicleFleetScreen(session: widget.session),
                ),
              );
              if (mounted) {
                await _load();
              }
            },
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Vehicles',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LogisticsOperationsScreen(session: widget.session),
                ),
              );
              if (mounted) {
                await _load();
              }
            },
            icon: const Icon(Icons.rule_folder_outlined),
            tooltip: 'Operations',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LogisticsReportsScreen(session: widget.session),
              ),
            ),
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Reports',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stock Movement',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Trip -> dispatch -> arrival -> receipt, with stock remaining authoritative in Inventory.',
                            ),
                          ],
                        ),
                      ),
                      if (_canCreate)
                        FilledButton.icon(
                          onPressed: _newTrip,
                          icon: const Icon(Icons.add_road),
                          label: const Text('New Trip'),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _summaryCard(
                        'Planned',
                        _count('planned'),
                        Icons.event_note_outlined,
                      ),
                      _summaryCard(
                        'Loading',
                        _count('loading'),
                        Icons.inventory_2_outlined,
                      ),
                      _summaryCard(
                        'In transit',
                        _count('in_transit'),
                        Icons.local_shipping_outlined,
                      ),
                      _summaryCard(
                        'Arrived',
                        _count('arrived'),
                        Icons.flag_outlined,
                      ),
                      _summaryCard(
                        'Ready to close',
                        _count('received'),
                        Icons.task_alt_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onSubmitted: (_) => _load(),
                          decoration: InputDecoration(
                            hintText:
                                'Search trip, transfer, vehicle, driver or location',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              onPressed: _load,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'active',
                            label: Text('Trips'),
                            icon: Icon(Icons.route_outlined),
                          ),
                          ButtonSegment(
                            value: 'incoming',
                            label: Text('Incoming'),
                            icon: Icon(Icons.call_received),
                          ),
                          ButtonSegment(
                            value: 'history',
                            label: Text('History'),
                            icon: Icon(Icons.history),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (value) =>
                            setState(() => _view = value.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_visibleTrips.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('No logistics trips found.')),
                      ),
                    )
                  else
                    ..._visibleTrips.map(_tripCard),
                ],
              ),
            ),
    );
  }
}

class LogisticsTripDialog extends StatefulWidget {
  final ClientSession session;
  final String tripId;
  final Future<void> Function() onChanged;

  const LogisticsTripDialog({
    super.key,
    required this.session,
    required this.tripId,
    required this.onChanged,
  });

  @override
  State<LogisticsTripDialog> createState() => _LogisticsTripDialogState();
}

class _LogisticsTripDialogState extends State<LogisticsTripDialog> {
  final LogisticsService _service = LogisticsService();
  bool _loading = true;
  bool _working = false;
  String? _error;
  Map<String, dynamic>? _detail;

  String get _tenantId => widget.session.business.id;
  Map<String, dynamic> get _trip =>
      Map<String, dynamic>.from((_detail?['trip'] as Map?) ?? const {});
  List<Map<String, dynamic>> get _documents =>
      ((_detail?['documents'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
  List<Map<String, dynamic>> get _events =>
      ((_detail?['events'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  bool get _canDispatch =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _service.detail(
        tenantId: _tenantId,
        tripId: widget.tripId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _clean(error);
        });
      }
    }
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ThqNotify.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String action = 'Confirm',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _textPrompt(
    String title,
    String label, {
    bool required = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (required && text.isEmpty) {
                return;
              }
              Navigator.pop(context, text);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      final result = await action();
      _message('${result['status'] ?? 'Updated'}');
      await _load();
      await widget.onChanged();
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _dispatch() async {
    if (!await _confirm(
      'Dispatch trip?',
      'This dispatches every linked approved stock transfer atomically. Stock, serials and batches will move to IN TRANSIT.',
      action: 'Dispatch',
    )) {
      return;
    }
    final note = await _textPrompt('Dispatch note', 'Optional note');
    if (note == null) {
      return;
    }
    await _run(
      () => _service.dispatch(
        tenantId: _tenantId,
        tripId: widget.tripId,
        note: note,
      ),
    );
  }

  Future<void> _receive(Map<String, dynamic> document) async {
    if (_working) {
      return;
    }

    setState(() => _working = true);
    try {
      final transferId = document['stock_transfer_id'].toString();
      final receiptContext = await _service.receiptContext(
        tenantId: _tenantId,
        tripId: widget.tripId,
        transferId: transferId,
      );

      if (!mounted) {
        return;
      }

      final draft = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            LogisticsReceiptDialog(receiptContext: receiptContext),
      );

      if (draft == null || !mounted) {
        return;
      }

      final lines = ((draft['lines'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final note = draft['note']?.toString() ?? '';

      final result = await _service.receiveTransferReconciled(
        tenantId: _tenantId,
        tripId: widget.tripId,
        transferId: transferId,
        lines: lines,
        note: note,
      );

      if (!mounted) {
        return;
      }

      final receiptNumber = result['receipt_number']?.toString();
      final hasVariance = result['has_variance'] == true;
      _message(
        hasVariance
            ? 'Received with variance${receiptNumber == null ? '' : ' ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¢ $receiptNumber'}'
            : 'Received${receiptNumber == null ? '' : ' ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¢ $receiptNumber'}',
      );

      await _load();
      await widget.onChanged();
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _cancel() async {
    final reason = await _textPrompt(
      'Cancel trip',
      'Cancellation reason',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) {
      return;
    }
    await _run(
      () => _service.cancel(
        tenantId: _tenantId,
        tripId: widget.tripId,
        reason: reason,
      ),
    );
  }

  Widget _statusChip(String status) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(status.replaceAll('_', ' ').toUpperCase()),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          width: 720,
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return AlertDialog(
        title: const Text('Logistics Trip'),
        content: SizedBox(width: 720, child: Text(_error!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final status = _trip['status']?.toString() ?? 'planned';
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(_trip['trip_number']?.toString() ?? 'Logistics Trip'),
          ),
          _statusChip(status),
        ],
      ),
      content: SizedBox(
        width: 880,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Route: ${_trip['from_location'] ?? '-'} -> ${_trip['to_location'] ?? '-'}',
                    ),
                    Text('Vehicle: ${_trip['vehicle_registration'] ?? '-'}'),
                    Text('Driver: ${_trip['driver_name'] ?? '-'}'),
                    if (_trip['planned_departure_at'] != null)
                      Text(
                        'Planned: ${_formatIso(_trip['planned_departure_at'])}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Stock Documents'),
                        Tab(text: 'Timeline'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView(
                            children: _documents.map((doc) {
                              final docStatus = doc['status']?.toString() ?? '';
                              final items =
                                  ((doc['items'] as List?) ?? const [])
                                      .whereType<Map>()
                                      .toList();
                              return Card(
                                child: ExpansionTile(
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          doc['transfer_number']?.toString() ??
                                              '-',
                                        ),
                                      ),
                                      _statusChip(docStatus),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${doc['item_count'] ?? 0} item(s) ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ Qty ${doc['total_quantity'] ?? 0} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ In transit ${doc['in_transit_quantity'] ?? 0}',
                                  ),
                                  trailing:
                                      status == 'arrived' &&
                                          docStatus != 'received' &&
                                          _canDispatch
                                      ? FilledButton.tonal(
                                          onPressed: _working
                                              ? null
                                              : () => _receive(doc),
                                          child: const Text('Receive'),
                                        )
                                      : null,
                                  children: items
                                      .map(
                                        (item) => ListTile(
                                          dense: true,
                                          title: Text(
                                            '${item['product_name'] ?? '-'} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ ${item['sku'] ?? '-'}',
                                          ),
                                          subtitle: Text(
                                            'Tracking: ${item['tracking_mode'] ?? 'none'}',
                                          ),
                                          trailing: Text(
                                            '${item['dispatched_quantity'] ?? 0} / ${item['quantity'] ?? 0}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              );
                            }).toList(),
                          ),
                          ListView(
                            children: _events.reversed
                                .map(
                                  (event) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.circle, size: 10),
                                    title: Text(
                                      (event['event_type']?.toString() ?? '')
                                          .replaceAll('_', ' '),
                                    ),
                                    subtitle: Text(
                                      _formatIso(event['created_at']),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_working)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if ((status == 'planned' || status == 'loading') && _canDispatch)
          TextButton(
            onPressed: _working ? null : _cancel,
            child: const Text('Cancel Trip'),
          ),
        if (status == 'planned')
          FilledButton.tonalIcon(
            onPressed: _working
                ? null
                : () => _run(
                    () => _service.startLoading(
                      tenantId: _tenantId,
                      tripId: widget.tripId,
                    ),
                  ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Start Loading'),
          ),
        if ((status == 'planned' || status == 'loading') && _canDispatch)
          FilledButton.icon(
            onPressed: _working ? null : _dispatch,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Dispatch'),
          ),
        if (status == 'in_transit' && _canDispatch)
          FilledButton.icon(
            onPressed: _working
                ? null
                : () => _run(
                    () => _service.arrive(
                      tenantId: _tenantId,
                      tripId: widget.tripId,
                    ),
                  ),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Mark Arrived'),
          ),
        if (status == 'received' && _canDispatch)
          FilledButton.icon(
            onPressed: _working
                ? null
                : () => _run(
                    () => _service.close(
                      tenantId: _tenantId,
                      tripId: widget.tripId,
                    ),
                  ),
            icon: const Icon(Icons.task_alt_outlined),
            label: const Text('Close Trip'),
          ),
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatIso(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return '-';
    }
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
