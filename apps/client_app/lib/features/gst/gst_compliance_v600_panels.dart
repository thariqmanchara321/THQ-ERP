import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'gst_compliance_v520_service.dart';
import 'gst_compliance_v600_api.dart';

class GstReturnsV600Panel extends StatefulWidget {
  const GstReturnsV600Panel({
    super.key,
    required this.service,
    required this.from,
    required this.to,
  });

  final GstComplianceV520Service service;
  final DateTime from;
  final DateTime to;

  @override
  State<GstReturnsV600Panel> createState() => _GstReturnsV600PanelState();
}

class _GstReturnsV600PanelState extends State<GstReturnsV600Panel> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _registrations = const [];
  String? _registrationId;
  Map<String, dynamic>? _period;
  Map<String, dynamic>? _workspace;
  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _lastAction;

  DateTime get _periodStart => DateTime(widget.from.year, widget.from.month, 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GstReturnsV600Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final registrations = await widget.service.listRegistrations();
      var selected = _registrationId;
      if (selected == null ||
          !registrations.any((r) => _id(r) == selected)) {
        selected = registrations.isEmpty ? null : _id(registrations.first);
      }

      Map<String, dynamic>? period;
      Map<String, dynamic>? workspace;
      Map<String, dynamic>? provider;

      if (selected != null && selected.isNotEmpty) {
        period = await widget.service.ensureReturnPeriod(
          registrationId: selected,
          periodStart: _periodStart,
        );
        workspace = await widget.service.loadReturnsWorkspace(
          registrationId: selected,
          periodStart: _periodStart,
        );
        provider = await widget.service.providerConnectionStatus(
          registrationId: selected,
        );
      }

      if (!mounted) return;
      setState(() {
        _registrations = registrations;
        _registrationId = selected;
        _period = period;
        _workspace = workspace;
        _provider = provider;
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

  Future<void> _run(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _lastAction = result);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String? get _periodId {
    final p = _period;
    if (p == null) return null;
    return _text(p['id'] ?? p['period_id']);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _registrations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return _V600Page(
      title: 'GST Returns',
      subtitle:
          'GSTR-1, GSTR-1A, GSTR-3B and GSTR-2B/IMS reconciliation from immutable GST evidence.',
      error: _error,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_registrations.isEmpty)
            const _V600Notice(
              icon: Icons.badge_outlined,
              title: 'No GST registration',
              message:
                  'Configure a GST registration before preparing statutory returns.',
            )
          else ...[
            _V600Card(
              title: 'Return period',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 340,
                    child: DropdownButtonFormField<String>(
                      initialValue: _registrationId,
                      decoration: const InputDecoration(
                        labelText: 'GST registration',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final row in _registrations)
                          DropdownMenuItem(
                            value: _id(row),
                            child: Text(
                              '${_text(row['gstin'])} • '
                              '${_text(row['legal_name'] ?? row['trade_name'])}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) {
                              setState(() => _registrationId = value);
                              _load();
                            },
                    ),
                  ),
                  _V600Pill(
                    label:
                        '${_periodStart.year}-${_periodStart.month.toString().padLeft(2, '0')}',
                    good: true,
                  ),
                  if (_period != null)
                    _V600Pill(
                      label: _text(
                        _period!['status'],
                        fallback: 'open',
                      ).toUpperCase(),
                      good: _text(_period!['status']) != 'filed',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _V600Card(
              title: 'Provider / portal actions',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _loading || _periodId == null
                        ? null
                        : () => _run(
                              () => widget.service.queueGstr2bFetch(
                                periodId: _periodId!,
                                requestId: _uuidV4(),
                              ),
                            ),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Fetch GSTR-2B'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading || _periodId == null
                        ? null
                        : () => _run(
                              () => widget.service.queueImsFetch(
                                periodId: _periodId!,
                                requestId: _uuidV4(),
                              ),
                            ),
                    icon: const Icon(Icons.sync_alt_outlined, size: 18),
                    label: const Text('Fetch IMS'),
                  ),
                  FilledButton.icon(
                    onPressed: !_canSubmit('gstr1')
                        ? null
                        : () => _run(
                              () => widget.service.queueGstr1(
                                periodId: _periodId!,
                                requestId: _uuidV4(),
                              ),
                            ),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Queue GSTR-1'),
                  ),
                  FilledButton.icon(
                    onPressed: !_canSubmit('gstr3b')
                        ? null
                        : () => _run(
                              () => widget.service.queueGstr3b(
                                periodId: _periodId!,
                                requestId: _uuidV4(),
                              ),
                            ),
                    icon: const Icon(Icons.cloud_done_outlined, size: 18),
                    label: const Text('Queue GSTR-3B'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading || _periodId == null
                        ? null
                        : () => _run(
                              () => widget.service.loadGstr1aPreview(
                                periodId: _periodId!,
                              ),
                            ),
                    icon: const Icon(Icons.edit_note_outlined, size: 18),
                    label: const Text('Preview GSTR-1A'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_provider != null)
              _V600JsonCard(title: 'Provider connection', data: _provider!),
            if (_provider != null) const SizedBox(height: 12),
            if (_workspace != null)
              _V600JsonCard(title: 'Returns workspace', data: _workspace!),
            if (_lastAction != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'Last action', data: _lastAction!),
            ],
          ],
        ],
      ),
    );
  }

  bool _canSubmit(String kind) {
    if (_loading || _periodId == null || !widget.service.can('submit')) {
      return false;
    }
    final p = _period ?? const <String, dynamic>{};
    final status = _text(p['status']);
    if (status == 'filed') return false;
    if (kind == 'gstr3b' && p['gstr1_filed_at'] == null) return false;
    return true;
  }
}

class GstEinvoiceV600Panel extends StatefulWidget {
  const GstEinvoiceV600Panel({
    super.key,
    required this.service,
    required this.from,
    required this.to,
  });

  final GstComplianceV520Service service;
  final DateTime from;
  final DateTime to;

  @override
  State<GstEinvoiceV600Panel> createState() => _GstEinvoiceV600PanelState();
}

class _GstEinvoiceV600PanelState extends State<GstEinvoiceV600Panel> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _documents = const [];
  int? _selectedIndex;
  String? _snapshotId;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _lastAction;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void didUpdateWidget(covariant GstEinvoiceV600Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _loadDocuments();
    }
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.listDocuments(
        from: widget.from,
        to: widget.to,
        evidenceStatus: 'authoritative',
        limit: 100,
      );
      final docs = _rows(data['items'] ?? data['rows']);
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _selectedIndex = docs.isEmpty ? null : 0;
        _loading = false;
      });
      if (docs.isNotEmpty) await _loadSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadSelected() async {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _documents.length) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = _documents[index];
      final evidence = await widget.service.loadDocumentEvidence(
        sourceType: _text(row['source_type'] ?? row['document_type']),
        sourceId: _text(row['source_id'] ?? row['id']),
      );
      final snapshot = _map(evidence['snapshot']);
      final snapshotId = _text(snapshot['id'] ?? snapshot['snapshot_id']);
      if (snapshotId.isEmpty) {
        throw const GstComplianceV520Exception(
          'Authoritative GST snapshot ID is missing.',
        );
      }
      final preview =
          await widget.service.loadEinvoicePreview(snapshotId: snapshotId);
      final status =
          await widget.service.loadProviderStatus(snapshotId: snapshotId);
      final registrationId =
          _text(preview['registration_id'] ?? snapshot['thq_registration_id']);
      final provider = await widget.service.providerConnectionStatus(
        registrationId: registrationId.isEmpty ? null : registrationId,
      );
      if (!mounted) return;
      setState(() {
        _snapshotId = snapshotId;
        _preview = preview;
        _status = status;
        _provider = provider;
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

  Future<void> _run(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _lastAction = result);
      await _loadSelected();
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
    return _V600Page(
      title: 'E-Invoice / IRN',
      subtitle:
          'Preview, queue, monitor, retry and cancel IRN operations from immutable GST snapshots.',
      error: _error,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _loadDocuments,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_documents.isEmpty && !_loading)
            const _V600Notice(
              icon: Icons.receipt_long_outlined,
              title: 'No authoritative GST documents',
              message:
                  'Create an authoritative GST transaction in the selected period first.',
            )
          else ...[
            _documentPicker(),
            const SizedBox(height: 12),
            _V600Card(
              title: 'IRN actions',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ||
                            _snapshotId == null ||
                            !widget.service.can('einvoice')
                        ? null
                        : () => _run(
                              () => widget.service.queueEinvoice(
                                snapshotId: _snapshotId!,
                                requestId: _uuidV4(),
                              ),
                            ),
                    icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                    label: const Text('Generate IRN'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ||
                            _snapshotId == null ||
                            !widget.service.can('cancel_irn')
                        ? null
                        : _cancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel IRN'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _failedJobId == null || _loading
                        ? null
                        : () => _run(
                              () => widget.service.retryProviderJob(
                                jobId: _failedJobId!,
                              ),
                            ),
                    icon: const Icon(Icons.replay_outlined, size: 18),
                    label: const Text('Retry failed job'),
                  ),
                ],
              ),
            ),
            if (_provider != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'Provider connection', data: _provider!),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'E-Invoice preview', data: _preview!),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'IRN lifecycle', data: _status!),
            ],
            if (_lastAction != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'Last action', data: _lastAction!),
            ],
          ],
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _documentPicker() {
    return _V600Card(
      title: 'Authoritative document',
      child: DropdownButtonFormField<int>(
        initialValue: _selectedIndex,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Document',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (var i = 0; i < _documents.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                '${_text(_documents[i]['document_number'] ?? _documents[i]['source_number'])}'
                ' • ${_text(_documents[i]['source_type'])}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _loading
            ? null
            : (value) {
                setState(() => _selectedIndex = value);
                _loadSelected();
              },
      ),
    );
  }

  String? get _failedJobId {
    for (final job in _rows(_status?['jobs'])) {
      if (_text(job['status']) == 'failed') return _text(job['job_id'] ?? job['id']);
    }
    return null;
  }

  Future<void> _cancel() async {
    final value = await showDialog<_CancelValue>(
      context: context,
      builder: (_) => const _CancelDialog(title: 'Cancel IRN'),
    );
    if (value == null || _snapshotId == null) return;
    await _run(
      () => widget.service.cancelIrnV600(
        snapshotId: _snapshotId!,
        requestId: _uuidV4(),
        reasonCode: value.reasonCode,
        remarks: value.remarks,
      ),
    );
  }
}

class GstEwaybillV600Panel extends StatefulWidget {
  const GstEwaybillV600Panel({
    super.key,
    required this.service,
    required this.from,
    required this.to,
  });

  final GstComplianceV520Service service;
  final DateTime from;
  final DateTime to;

  @override
  State<GstEwaybillV600Panel> createState() => _GstEwaybillV600PanelState();
}

class _GstEwaybillV600PanelState extends State<GstEwaybillV600Panel> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _documents = const [];
  int? _selectedIndex;
  String? _snapshotId;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _lastAction;

  String _mode = 'road';
  final _distance = TextEditingController();
  final _vehicle = TextEditingController();
  final _transporterId = TextEditingController();
  final _transporterName = TextEditingController();
  final _transportDocNo = TextEditingController();
  final _transportDocDate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void didUpdateWidget(covariant GstEwaybillV600Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _loadDocuments();
    }
  }

  @override
  void dispose() {
    _distance.dispose();
    _vehicle.dispose();
    _transporterId.dispose();
    _transporterName.dispose();
    _transportDocNo.dispose();
    _transportDocDate.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _transport => {
        'mode': _mode,
        if (_distance.text.trim().isNotEmpty)
          'distance_km': num.tryParse(_distance.text.trim()),
        if (_vehicle.text.trim().isNotEmpty)
          'vehicle_no': _vehicle.text.trim().toUpperCase(),
        if (_transporterId.text.trim().isNotEmpty)
          'transporter_id': _transporterId.text.trim().toUpperCase(),
        if (_transporterName.text.trim().isNotEmpty)
          'transporter_name': _transporterName.text.trim(),
        if (_transportDocNo.text.trim().isNotEmpty)
          'document_no': _transportDocNo.text.trim(),
        if (_transportDocDate.text.trim().isNotEmpty)
          'document_date': _transportDocDate.text.trim(),
      };

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.listDocuments(
        from: widget.from,
        to: widget.to,
        evidenceStatus: 'authoritative',
        limit: 100,
      );
      final docs = _rows(data['items'] ?? data['rows']);
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _selectedIndex = docs.isEmpty ? null : 0;
        _loading = false;
      });
      if (docs.isNotEmpty) await _loadSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadSelected() async {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _documents.length) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = _documents[index];
      final evidence = await widget.service.loadDocumentEvidence(
        sourceType: _text(row['source_type'] ?? row['document_type']),
        sourceId: _text(row['source_id'] ?? row['id']),
      );
      final snapshot = _map(evidence['snapshot']);
      final snapshotId = _text(snapshot['id'] ?? snapshot['snapshot_id']);
      if (snapshotId.isEmpty) {
        throw const GstComplianceV520Exception(
          'Authoritative GST snapshot ID is missing.',
        );
      }
      final preview = await widget.service.loadEwaybillPreview(
        snapshotId: snapshotId,
        transport: _transport,
      );
      final status =
          await widget.service.loadProviderStatus(snapshotId: snapshotId);
      final registrationId =
          _text(preview['registration_id'] ?? snapshot['thq_registration_id']);
      final provider = await widget.service.providerConnectionStatus(
        registrationId: registrationId.isEmpty ? null : registrationId,
      );
      if (!mounted) return;
      setState(() {
        _snapshotId = snapshotId;
        _preview = preview;
        _status = status;
        _provider = provider;
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

  Future<void> _run(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _lastAction = result);
      await _loadSelected();
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
    return _V600Page(
      title: 'E-Way Bill',
      subtitle:
          'Validate movement data, queue generation, monitor provider status and cancel within statutory rules.',
      error: _error,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _loadDocuments,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_documents.isEmpty && !_loading)
            const _V600Notice(
              icon: Icons.local_shipping_outlined,
              title: 'No authoritative GST documents',
              message:
                  'Create an authoritative goods transaction in the selected period first.',
            )
          else ...[
            _V600Card(
              title: 'Authoritative document',
              child: DropdownButtonFormField<int>(
                initialValue: _selectedIndex,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Document',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var i = 0; i < _documents.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${_text(_documents[i]['document_number'] ?? _documents[i]['source_number'])}'
                        ' • ${_text(_documents[i]['source_type'])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _selectedIndex = value);
                        _loadSelected();
                      },
              ),
            ),
            const SizedBox(height: 12),
            _transportCard(),
            const SizedBox(height: 12),
            _V600Card(
              title: 'E-Way Bill actions',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading || _snapshotId == null
                        ? null
                        : _loadSelected,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Validate / Preview'),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ||
                            _snapshotId == null ||
                            !widget.service.can('ewaybill')
                        ? null
                        : () => _run(
                              () => widget.service.queueEwaybill(
                                snapshotId: _snapshotId!,
                                requestId: _uuidV4(),
                                transport: _transport,
                              ),
                            ),
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Generate E-Way Bill'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ||
                            _snapshotId == null ||
                            !widget.service.can('ewaybill')
                        ? null
                        : _cancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel E-Way Bill'),
                  ),
                ],
              ),
            ),
            if (_provider != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'Provider connection', data: _provider!),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'E-Way Bill preview', data: _preview!),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'E-Way Bill lifecycle', data: _status!),
            ],
            if (_lastAction != null) ...[
              const SizedBox(height: 12),
              _V600JsonCard(title: 'Last action', data: _lastAction!),
            ],
          ],
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _transportCard() {
    return _V600Card(
      title: 'Transport details',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                labelText: 'Mode',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'road', child: Text('Road')),
                DropdownMenuItem(value: 'rail', child: Text('Rail')),
                DropdownMenuItem(value: 'air', child: Text('Air')),
                DropdownMenuItem(value: 'ship', child: Text('Ship')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _mode = value);
              },
            ),
          ),
          _field(_distance, 'Distance km', 160, numeric: true),
          _field(_vehicle, 'Vehicle no.', 180),
          _field(_transporterId, 'Transporter ID', 190),
          _field(_transporterName, 'Transporter name', 220),
          _field(_transportDocNo, 'Transport document no.', 220),
          _field(_transportDocDate, 'Document date YYYY-MM-DD', 230),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    double width, {
    bool numeric = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
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

  Future<void> _cancel() async {
    final value = await showDialog<_CancelValue>(
      context: context,
      builder: (_) => const _CancelDialog(title: 'Cancel E-Way Bill'),
    );
    if (value == null || _snapshotId == null) return;
    await _run(
      () => widget.service.cancelEwaybill(
        snapshotId: _snapshotId!,
        requestId: _uuidV4(),
        reasonCode: value.reasonCode,
        remarks: value.remarks,
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.title});

  final String title;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  String _reason = '1';
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason code',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: '1', child: Text('1')),
                DropdownMenuItem(value: '2', child: Text('2')),
                DropdownMenuItem(value: '3', child: Text('3')),
                DropdownMenuItem(value: '4', child: Text('4')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _reason = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _remarks,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                border: OutlineInputBorder(),
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
        FilledButton(
          onPressed: () {
            final text = _remarks.text.trim();
            if (text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Remarks are required.')),
              );
              return;
            }
            Navigator.pop(
              context,
              _CancelValue(reasonCode: _reason, remarks: text),
            );
          },
          child: const Text('Queue cancellation'),
        ),
      ],
    );
  }
}

class _CancelValue {
  const _CancelValue({
    required this.reasonCode,
    required this.remarks,
  });

  final String reasonCode;
  final String remarks;
}

class _V600Page extends StatelessWidget {
  const _V600Page({
    required this.title,
    required this.subtitle,
    required this.child,
    this.error,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Object? error;
  final List<Widget> actions;

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
                  constraints: const BoxConstraints(minWidth: 280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
            if (error != null) ...[
              const SizedBox(height: 10),
              _V600Notice(
                icon: Icons.error_outline,
                title: 'GST action failed',
                message: error.toString(),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _V600Card extends StatelessWidget {
  const _V600Card({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: .3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _V600Notice extends StatelessWidget {
  const _V600Notice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _V600Card(
      title: title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 9),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _V600JsonCard extends StatelessWidget {
  const _V600JsonCard({
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    return _V600Card(
      title: title,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: title.contains('workspace') ||
            title.contains('preview') ||
            title.contains('connection'),
        title: Text(
          _summary(data),
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summary(Map<String, dynamic> data) {
    for (final key in const [
      'status',
      'ready',
      'connection_status',
      'period_start',
      'job_id',
    ]) {
      if (data[key] != null) return '$key: ${data[key]}';
    }
    return '${data.length} field(s)';
  }
}

class _V600Pill extends StatelessWidget {
  const _V600Pill({
    required this.label,
    required this.good,
  });

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: good ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _id(Map<String, dynamic> row) =>
    _text(row['id'] ?? row['registration_id']);

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _rows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
