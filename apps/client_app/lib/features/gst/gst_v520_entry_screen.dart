import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/client_session.dart';
import 'gst_compliance_v520_screen.dart';
import 'gst_compliance_v520_service.dart';

/// Entry gate for the v5.2 GST workspace.
///
/// Every tenant must explicitly choose GST Registered or Non-GST. Both modes
/// use v5.2 authoritative writers; Non-GST never falls back to v5.1.
class GstV520EntryScreen extends StatefulWidget {
  const GstV520EntryScreen({super.key, required this.session});

  final ClientSession session;

  @override
  State<GstV520EntryScreen> createState() => _GstV520EntryScreenState();
}

class _GstV520EntryScreenState extends State<GstV520EntryScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  bool _loading = true;
  String _taxMode = 'unconfigured';
  Object? _error;

  String get _tenantId => widget.session.business.id;
  bool get _configured => _taxMode == 'gst_registered' || _taxMode == 'non_gst';

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _client.rpc(
        'gst_tax_mode_get_v520',
        params: {
          'p_tenant_id': _tenantId,
          'p_date': _date(DateTime.now()),
        },
      );
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _taxMode = map['tax_mode']?.toString() ?? 'unconfigured';
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

  Future<void> _configure({bool changing = false}) async {
    final choice = await showDialog<_TaxModeChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaxModeDialog(
        currentMode: _taxMode,
        changing: changing,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'gst_tax_mode_set_v520',
        params: {
          'p_tenant_id': _tenantId,
          'p_tax_mode': choice.mode,
          'p_effective_from': _date(choice.effectiveFrom),
          'p_reason': choice.reason.trim().isEmpty ? null : choice.reason.trim(),
        },
      );
      await _loadMode();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_configured) {
      return _TaxModeRequired(
        error: _error,
        onConfigure: () => _configure(),
      );
    }

    final service = GstComplianceV520Service(
      client: _client,
      tenantId: _tenantId,
    );

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _taxMode == 'gst_registered'
                      ? Icons.verified_outlined
                      : Icons.block_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _taxMode == 'gst_registered'
                        ? 'Tax mode: GST Registered • authoritative GST v5.2'
                        : 'Tax mode: Non-GST • v5.2 writer with zero GST',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_error != null)
                  Flexible(
                    child: Text(
                      _error.toString(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _configure(changing: true),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Change'),
                ),
                IconButton(
                  tooltip: 'Refresh tax mode',
                  onPressed: _loadMode,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: GstComplianceV520Screen(
            service: service,
          ),
        ),
      ],
    );
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _TaxModeRequired extends StatelessWidget {
  const _TaxModeRequired({
    required this.error,
    required this.onConfigure,
  });

  final Object? error;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.policy_outlined, size: 52),
                const SizedBox(height: 14),
                Text(
                  'Choose the business tax mode',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'THQ ERP v5.2 will not create tax-bearing transactions until '
                  'the business is explicitly marked GST Registered or Non-GST. '
                  'Non-GST businesses still use the v5.2 authoritative writer '
                  'with GST amounts fixed to zero; there is no legacy fallback.',
                  textAlign: TextAlign.center,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.tune),
                  label: const Text('Configure tax mode'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaxModeChoice {
  const _TaxModeChoice({
    required this.mode,
    required this.effectiveFrom,
    required this.reason,
  });

  final String mode;
  final DateTime effectiveFrom;
  final String reason;
}

class _TaxModeDialog extends StatefulWidget {
  const _TaxModeDialog({
    required this.currentMode,
    required this.changing,
  });

  final String currentMode;
  final bool changing;

  @override
  State<_TaxModeDialog> createState() => _TaxModeDialogState();
}

class _TaxModeDialogState extends State<_TaxModeDialog> {
  late String _mode;
  DateTime _effectiveFrom = DateTime.now();
  final TextEditingController _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mode = widget.currentMode == 'non_gst' ? 'non_gst' : 'gst_registered';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => _effectiveFrom = value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.changing ? 'Change tax mode' : 'Set tax mode'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: _mode,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _mode = value);
                }
              },
              child: Column(
                children: const [
                  RadioListTile<String>(
                    value: 'gst_registered',
                    title: Text('GST Registered'),
                    subtitle: Text(
                      'THQ calculates CGST/SGST/UTGST/IGST/cess on the server from '
                      'effective GST masters and posts component accounting.',
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'non_gst',
                    title: Text('Non-GST'),
                    subtitle: Text(
                      'THQ still uses the v5.2 authoritative writer, but GST amounts '
                      'are zero. It never falls back to a legacy transaction writer.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Effective from'),
              subtitle: Text(
                '${_effectiveFrom.day.toString().padLeft(2, '0')}-'
                '${_effectiveFrom.month.toString().padLeft(2, '0')}-'
                '${_effectiveFrom.year}',
              ),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Change date'),
              ),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason / note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            const Text(
              'The server audits this change and will reject an effective date '
              'that conflicts with already-posted authoritative documents.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _TaxModeChoice(
              mode: _mode,
              effectiveFrom: _effectiveFrom,
              reason: _reason.text,
            ),
          ),
          child: const Text('Save tax mode'),
        ),
      ],
    );
  }
}
