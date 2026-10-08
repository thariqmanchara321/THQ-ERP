import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

class TrackingConversionDialog extends StatefulWidget {
  final Map<String, dynamic> preview;
  final String mode;
  final String productName;
  const TrackingConversionDialog({
    super.key,
    required this.preview,
    required this.mode,
    required this.productName,
  });

  @override
  State<TrackingConversionDialog> createState() =>
      _TrackingConversionDialogState();
}

class _TrackingConversionDialogState extends State<TrackingConversionDialog> {
  final _reason = TextEditingController();
  late final List<Map<String, dynamic>> _locations;
  late final List<TextEditingController> _inputs;
  bool _synced = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locations = (widget.preview['locations'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    _inputs = List.generate(
      _locations.length,
      (i) => TextEditingController(
        text: widget.mode == 'batch' && (_number(_locations[i]['quantity']) > 0)
            ? 'CONV-$stamp-${i + 1}=${_locations[i]['quantity']}'
            : '',
      ),
    );
  }

  double _number(dynamic value) => double.tryParse(value.toString()) ?? 0;

  @override
  void dispose() {
    _reason.dispose();
    for (final c in _inputs) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    try {
      if (!_synced) {
        throw const FormatException('Confirm that all devices have synced.');
      }
      if (_reason.text.trim().length < 5) {
        throw const FormatException(
          'Enter a reason with at least 5 characters.',
        );
      }
      final locations = <Map<String, dynamic>>[];
      for (var i = 0; i < _locations.length; i++) {
        final q = _number(_locations[i]['quantity']);
        locations.add({
          'location_id': _locations[i]['location_id'],
          'expected_quantity': q,
          if (widget.mode == 'serial')
            'serial_numbers': parseTrackingSerials(_inputs[i].text, q),
          if (widget.mode == 'batch')
            'batches': parseTrackingBatches(_inputs[i].text, q),
        });
      }
      Navigator.pop(context, <String, dynamic>{
        'locations': locations,
        'reason': _reason.text.trim(),
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockers = (widget.preview['blockers'] as List? ?? const []);
    final history = (widget.preview['history'] as List? ?? const []);
    return AlertDialog(
      title: Text('Change tracking: ${widget.productName}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.preview['mode']} → ${widget.mode}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Stock quantity and value stay the same. Existing invoice history and warranties remain available. New transactions follow the selected tracking method.',
              ),
              if (widget.mode == 'none') ...[
                const SizedBox(height: 8),
                const Text(
                  'New sales will no longer require serials or batches. Batch expiry checks and automatic tracking warranties stop for new sales.',
                ),
              ],
              for (final b in blockers)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    b.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (var i = 0; i < _locations.length; i++) ...[
                const SizedBox(height: 16),
                Text(
                  '${_locations[i]['name']}: ${_locations[i]['quantity']} base units',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.mode != 'none')
                  TextField(
                    controller: _inputs[i],
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: widget.mode == 'serial'
                          ? 'One serial number per base unit'
                          : 'New batch allocations',
                      helperText: widget.mode == 'serial'
                          ? 'Enter existing labels, one per line.'
                          : 'One per line: BATCH=QUANTITY|YYYY-MM-DD (expiry optional unless required).',
                      border: const OutlineInputBorder(),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for the change',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _synced,
                title: const Text(
                  'All POS/mobile devices have synced pending invoices',
                ),
                subtitle: const Text(
                  'Refresh their catalogues after conversion. Older queued invoices will require review.',
                ),
                onChanged: (v) => setState(() => _synced = v == true),
              ),
              if (history.isNotEmpty) ...[
                const Divider(),
                const Text('Previous changes'),
                for (final h in history.take(5))
                  if (h is Map)
                    Text(
                      '${h['at']}: ${h['from']} → ${h['to']} · ${h['reason']}',
                    ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: blockers.isEmpty ? _confirm : null,
          child: const Text('Confirm Conversion'),
        ),
      ],
    );
  }
}
