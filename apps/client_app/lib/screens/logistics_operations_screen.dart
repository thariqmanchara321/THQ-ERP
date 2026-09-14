import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/logistics_service.dart';

class LogisticsOperationsScreen extends StatefulWidget {
  final ClientSession session;

  const LogisticsOperationsScreen({super.key, required this.session});

  @override
  State<LogisticsOperationsScreen> createState() =>
      _LogisticsOperationsScreenState();
}

class _LogisticsOperationsScreenState extends State<LogisticsOperationsScreen>
    with SingleTickerProviderStateMixin {
  final LogisticsService _service = LogisticsService();

  late final TabController _tabs;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _exceptionFilter = 'active';
  String? _evidenceTripId;
  String? _evidenceTransferId;
  String? _evidenceReceiptId;

  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _exceptions = [];
  List<Map<String, dynamic>> _evidence = [];

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.operationsTrips(tenantId: _tenantId, locationId: _locationId),
        _service.logisticsExceptions(
          tenantId: _tenantId,
          locationId: _locationId,
        ),
      ]);
      if (!mounted) {
        return;
      }
      final trips = results[0];
      final exceptions = results[1];
      String? selected = _evidenceTripId;
      if (selected == null ||
          !trips.any((row) => row['id']?.toString() == selected)) {
        selected = trips.isEmpty ? null : trips.first['id']?.toString();
      }
      setState(() {
        _trips = trips;
        _exceptions = exceptions;
        _evidenceTripId = selected;
      });
      await _loadEvidence(showLoading: false);
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

  Future<void> _loadEvidence({bool showLoading = true}) async {
    final tripId = _evidenceTripId;
    if (tripId == null) {
      if (mounted) {
        setState(() => _evidence = []);
      }
      return;
    }
    if (showLoading && mounted) {
      setState(() => _busy = true);
    }
    try {
      final rows = await _service.logisticsEvidence(
        tenantId: _tenantId,
        tripId: tripId,
      );
      if (mounted) {
        setState(() => _evidence = rows);
      }
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (showLoading && mounted) {
        setState(() => _busy = false);
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

  List<Map<String, dynamic>> get _overdueTrips =>
      _trips.where((row) => row['is_overdue'] == true).toList(growable: false);

  List<Map<String, dynamic>> get _visibleExceptions {
    if (_exceptionFilter == 'all') {
      return _exceptions;
    }
    if (_exceptionFilter == 'active') {
      return _exceptions
          .where(
            (row) =>
                row['status']?.toString() == 'open' ||
                row['status']?.toString() == 'investigating',
          )
          .toList(growable: false);
    }
    return _exceptions
        .where((row) => row['status']?.toString() == _exceptionFilter)
        .toList(growable: false);
  }

  int get _activeExceptionCount => _exceptions
      .where(
        (row) =>
            row['status']?.toString() == 'open' ||
            row['status']?.toString() == 'investigating',
      )
      .length;

  int get _evidenceCount =>
      _trips.fold<int>(0, (total, row) => total + _int(row['evidence_count']));

  int _int(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _qty(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    if (number == number.roundToDouble()) {
      return number.toInt().toString();
    }
    return number.toStringAsFixed(2);
  }

  String _date(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return '-';
    }
    final date = DateTime.tryParse(text)?.toLocal();
    if (date == null) {
      return text;
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _evidenceLabel(String value) {
    const labels = {
      'dispatch_photo': 'Dispatch photo',
      'arrival_photo': 'Arrival photo',
      'delivery_photo': 'Delivery photo',
      'damage_photo': 'Damage photo',
      'other': 'Other proof',
    };
    return labels[value] ?? value.replaceAll('_', ' ');
  }

  Future<void> _focusEvidence(
    String tripId, {
    String? transferId,
    String? receiptId,
  }) async {
    setState(() {
      _evidenceTripId = tripId;
      _evidenceTransferId = transferId;
      _evidenceReceiptId = receiptId;
    });
    _tabs.animateTo(2);
    await _loadEvidence();
  }

  Future<void> _updateException(Map<String, dynamic> row) async {
    String status = row['status']?.toString() ?? 'open';
    String? code = row['resolution_code']?.toString();
    final note = TextEditingController(
      text: row['resolution_note']?.toString() ?? '',
    );
    final reference = TextEditingController(
      text: row['external_reference']?.toString() ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            '${row['exception_type']?.toString().toUpperCase() ?? 'EXCEPTION'}'
            ' â€¢ ${row['trip_number'] ?? '-'}',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${row['product_name'] ?? 'Product'}'
                    '${(row['sku']?.toString() ?? '').isEmpty ? '' : ' â€¢ ${row['sku']}'}'
                    ' â€¢ Qty ${_qty(row['quantity'])}',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'investigating',
                        child: Text('Investigating'),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('Resolved'),
                      ),
                      DropdownMenuItem(value: 'waived', child: Text('Waived')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => status = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: code,
                    decoration: const InputDecoration(
                      labelText: 'Resolution / action',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'found_recovered',
                        child: Text('Found / recovered'),
                      ),
                      DropdownMenuItem(
                        value: 'damage_assessed',
                        child: Text('Damage assessed'),
                      ),
                      DropdownMenuItem(
                        value: 'carrier_claim',
                        child: Text('Carrier claim'),
                      ),
                      DropdownMenuItem(
                        value: 'insurance_claim',
                        child: Text('Insurance claim'),
                      ),
                      DropdownMenuItem(
                        value: 'writeoff_pending',
                        child: Text('Write-off pending'),
                      ),
                      DropdownMenuItem(
                        value: 'inventory_adjustment_reference',
                        child: Text('Inventory adjustment reference'),
                      ),
                      DropdownMenuItem(value: 'waived', child: Text('Waived')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setLocalState(() => code = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Resolution / investigation note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'External reference (optional)',
                      hintText: 'Claim, stock adjustment, ticket, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This records the operational outcome only. '
                    'It does not change stock or post accounting.',
                    style: TextStyle(fontSize: 12),
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
            FilledButton(
              onPressed: () {
                if ((status == 'resolved' || status == 'waived') &&
                    (code == null || code!.trim().isEmpty)) {
                  _message('Select a resolution / action.');
                  return;
                }
                if ((status == 'resolved' || status == 'waived') &&
                    note.text.trim().isEmpty) {
                  _message('Enter a resolution note.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _busy = true);
      try {
        await _service.updateLogisticsException(
          tenantId: _tenantId,
          exceptionId: row['id'].toString(),
          status: status,
          resolutionCode: code,
          resolutionNote: note.text,
          externalReference: reference.text,
        );
        _message('Exception updated.');
        await _load();
      } catch (error) {
        _message(_clean(error));
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
    }

    note.dispose();
    reference.dispose();
  }

  Future<void> _addEvidence() async {
    final tripId = _evidenceTripId;
    if (tripId == null) {
      _message('Select a trip first.');
      return;
    }

    String type = 'delivery_photo';
    final note = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Logistics Proof'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Proof type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'dispatch_photo',
                      child: Text('Dispatch photo'),
                    ),
                    DropdownMenuItem(
                      value: 'arrival_photo',
                      child: Text('Arrival photo'),
                    ),
                    DropdownMenuItem(
                      value: 'delivery_photo',
                      child: Text('Delivery / receipt photo'),
                    ),
                    DropdownMenuItem(
                      value: 'damage_photo',
                      child: Text('Damage photo'),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text('Other proof'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setLocalState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'JPEG or PNG only, maximum 5 MB. '
                    'Proof is retained as logistics audit evidence.',
                    style: TextStyle(fontSize: 12),
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
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.attach_file),
              label: const Text('Choose Image'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      note.dispose();
      return;
    }

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Proof image', extensions: ['jpg', 'jpeg', 'png']),
      ],
    );
    if (file == null || !mounted) {
      note.dispose();
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _message('The selected file is empty.');
      note.dispose();
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _message('The selected image is larger than 5 MB.');
      note.dispose();
      return;
    }

    final lowerName = file.name.toLowerCase();
    final mimeType = lowerName.endsWith('.png') ? 'image/png' : 'image/jpeg';

    setState(() => _busy = true);
    try {
      await _service.uploadLogisticsEvidence(
        tenantId: _tenantId,
        tripId: tripId,
        evidenceType: type,
        fileName: file.name,
        mimeType: mimeType,
        bytes: bytes,
        note: note.text,
        stockTransferId: _evidenceTransferId,
        receiptId: _evidenceReceiptId,
      );
      _message('Proof added.');
      setState(() {
        _evidenceTransferId = null;
        _evidenceReceiptId = null;
      });
      await _load();
      if (mounted) {
        _tabs.animateTo(2);
      }
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      note.dispose();
    }
  }

  Future<void> _viewEvidence(Map<String, dynamic> row) async {
    final path = row['storage_path']?.toString() ?? '';
    if (path.isEmpty) {
      return;
    }
    final url = _service.logisticsEvidencePublicUrl(path);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  _evidenceLabel(row['evidence_type']?.toString() ?? ''),
                ),
                subtitle: Text(
                  '${row['file_name'] ?? '-'} â€¢ ${_date(row['captured_at'])}',
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Unable to load proof image.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String label, int value, IconData icon) => SizedBox(
    width: 175,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
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
            ),
          ],
        ),
      ),
    ),
  );

  Widget _empty(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );

  Widget _overdueTab() {
    final rows = _overdueTrips;
    if (rows.isEmpty) {
      return _empty('No overdue logistics trips.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = rows[index];
        final kind = row['overdue_kind']?.toString() ?? 'trip';
        final due = kind == 'departure'
            ? row['planned_departure_at']
            : row['expected_arrival_date'];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: Text(
              '${row['trip_number'] ?? '-'} â€¢ '
              '${row['vehicle_registration'] ?? '-'}',
            ),
            subtitle: Text(
              '${row['from_location'] ?? '-'} â†’ ${row['to_location'] ?? '-'}\n'
              '${kind == 'departure' ? 'Departure' : 'Arrival'} overdue since ${_date(due)}'
              '${(row['driver_name']?.toString() ?? '').isEmpty ? '' : ' â€¢ ${row['driver_name']}'}',
            ),
            isThreeLine: true,
            trailing: FilledButton.tonalIcon(
              onPressed: () => _focusEvidence(row['id'].toString()),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Proof'),
            ),
          ),
        );
      },
    );
  }

  Widget _exceptionsTab() {
    final rows = _visibleExceptions;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              const Text('Show'),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _exceptionFilter,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(
                    value: 'investigating',
                    child: Text('Investigating'),
                  ),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'waived', child: Text('Waived')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _exceptionFilter = value);
                  }
                },
              ),
              const Spacer(),
              Text('${rows.length} item(s)'),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _empty('No logistics exceptions for this filter.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final type =
                        row['exception_type']?.toString() ?? 'exception';
                    final status = row['status']?.toString() ?? 'open';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              type == 'damaged'
                                  ? Icons.broken_image_outlined
                                  : Icons.help_outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        type.toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(status.toUpperCase()),
                                      ),
                                      Text('Qty ${_qty(row['quantity'])}'),
                                    ],
                                  ),
                                  Text(
                                    '${row['product_name'] ?? 'Product'}'
                                    '${(row['sku']?.toString() ?? '').isEmpty ? '' : ' â€¢ ${row['sku']}'}',
                                  ),
                                  Text(
                                    '${row['trip_number'] ?? '-'}'
                                    ' â€¢ ${row['transfer_number'] ?? '-'}'
                                    ' â€¢ ${row['receipt_number'] ?? '-'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    '${row['from_location'] ?? '-'} â†’ ${row['to_location'] ?? '-'}'
                                    ' â€¢ ${row['vehicle_registration'] ?? '-'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if ((row['resolution_note']?.toString() ?? '')
                                      .isNotEmpty)
                                    Text(
                                      'Resolution: ${row['resolution_note']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _updateException(row),
                                  icon: const Icon(Icons.edit_note),
                                  label: const Text('Update'),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _focusEvidence(
                                          row['trip_id'].toString(),
                                          transferId: row['stock_transfer_id']
                                              ?.toString(),
                                          receiptId: row['receipt_id']
                                              ?.toString(),
                                        ),
                                  icon: const Icon(Icons.add_a_photo_outlined),
                                  label: const Text('Proof'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _evidenceTab() {
    if (_trips.isEmpty) {
      return _empty('No logistics trips are available.');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _evidenceTripId,
                  decoration: const InputDecoration(
                    labelText: 'Trip',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _trips
                      .map(
                        (row) => DropdownMenuItem(
                          value: row['id'].toString(),
                          child: Text(
                            '${row['trip_number'] ?? '-'} â€¢ '
                            '${row['vehicle_registration'] ?? '-'} â€¢ '
                            '${row['from_location'] ?? '-'} â†’ ${row['to_location'] ?? '-'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) async {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _evidenceTripId = value;
                            _evidenceTransferId = null;
                            _evidenceReceiptId = null;
                          });
                          await _loadEvidence();
                        },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _addEvidence,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add Proof'),
              ),
            ],
          ),
        ),
        if (_evidenceTransferId != null || _evidenceReceiptId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.link, size: 18),
                label: const Text('Proof will be linked to selected exception'),
                onDeleted: () => setState(() {
                  _evidenceTransferId = null;
                  _evidenceReceiptId = null;
                }),
              ),
            ),
          ),
        Expanded(
          child: _evidence.isEmpty
              ? _empty('No proof images recorded for this trip.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _evidence.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = _evidence[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: Text(
                          _evidenceLabel(
                            row['evidence_type']?.toString() ?? '',
                          ),
                        ),
                        subtitle: Text(
                          '${row['file_name'] ?? '-'}'
                          ' â€¢ ${_date(row['captured_at'])}'
                          '${(row['note']?.toString() ?? '').isEmpty ? '' : '\n${row['note']}'}',
                        ),
                        isThreeLine: (row['note']?.toString() ?? '').isNotEmpty,
                        trailing: OutlinedButton.icon(
                          onPressed: () => _viewEvidence(row),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logistics Operations'),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricCard(
                        'Overdue Trips',
                        _overdueTrips.length,
                        Icons.schedule_outlined,
                      ),
                      _metricCard(
                        'Open Exceptions',
                        _activeExceptionCount,
                        Icons.report_problem_outlined,
                      ),
                      _metricCard(
                        'Proof Images',
                        _evidenceCount,
                        Icons.photo_library_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabs,
                    tabs: const [
                      Tab(icon: Icon(Icons.schedule), text: 'Overdue'),
                      Tab(
                        icon: Icon(Icons.rule_folder_outlined),
                        text: 'Exceptions',
                      ),
                      Tab(icon: Icon(Icons.photo_library), text: 'Evidence'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      children: [
                        TabBarView(
                          controller: _tabs,
                          children: [
                            _overdueTab(),
                            _exceptionsTab(),
                            _evidenceTab(),
                          ],
                        ),
                        if (_busy)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
