import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/client_session.dart';
import '../../services/location_scope_service.dart';
import 'audit_intelligence_service.dart';
import 'evidence_detail_dialog.dart';
import 'models/audit_evidence_models.dart';

class EvidenceExplorerView extends StatefulWidget {
  const EvidenceExplorerView({
    super.key,
    required this.session,
    required this.service,
    required this.from,
    required this.to,
    required this.onPickPeriod,
  });

  final ClientSession session;
  final AuditIntelligenceService service;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickPeriod;

  @override
  State<EvidenceExplorerView> createState() => _EvidenceExplorerViewState();
}

class _EvidenceExplorerViewState extends State<EvidenceExplorerView> {
  final _search = TextEditingController();
  Timer? _debounce;

  bool _loadingCatalog = false;
  bool _loadingEvidence = false;
  bool _exporting = false;

  String? _catalogError;
  String? _evidenceError;

  Map<String, List<AuditCatalogItem>> _groupedCatalog = {};

  String _selectedGroup = 'Sales';
  AuditCatalogItem? _selectedDataset;

  AuditEvidencePage? _page;
  int _offset = 0;
  int _requestSeq = 0;

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void didUpdateWidget(covariant EvidenceExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _offset = 0;
      _loadEvidence();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });

    try {
      final items = await widget.service.evidenceCatalog(
        tenantId: _tenantId,
        locationId: _locationId,
      );

      final grouped = <String, List<AuditCatalogItem>>{};
      for (final item in items) {
        grouped.putIfAbsent(item.group, () => []).add(item);
      }

      var defaultGroup = 'Sales';
      if (!grouped.containsKey(defaultGroup) && grouped.isNotEmpty) {
        defaultGroup = grouped.keys.first;
      }

      AuditCatalogItem? defaultDataset;
      if (grouped.containsKey(defaultGroup) && grouped[defaultGroup]!.isNotEmpty) {
        defaultDataset = grouped[defaultGroup]!.firstWhere(
          (d) => d.key == 'sales',
          orElse: () => grouped[defaultGroup]!.first,
        );
      }

      if (!mounted) return;
      setState(() {
        _groupedCatalog = grouped;
        _selectedGroup = defaultGroup;
        _selectedDataset = defaultDataset;
        _loadingCatalog = false;
      });

      if (_selectedDataset != null) {
        _offset = 0;
        _loadEvidence();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _catalogError = 'Could not load evidence catalog: $e';
      });
    }
  }

  Future<void> _loadEvidence() async {
    if (_selectedDataset == null) return;
    _debounce?.cancel();
    final seq = ++_requestSeq;

    setState(() {
      _loadingEvidence = true;
      _evidenceError = null;
    });

    try {
      final page = await widget.service.evidence(
        tenantId: _tenantId,
        dataset: _selectedDataset!.key,
        from: widget.from,
        to: widget.to,
        locationId: _locationId,
        query: _search.text.trim(),
        offset: _offset,
        limit: 50,
      );

      if (!mounted || seq != _requestSeq) return;

      if (_offset > 0 && page.rows.isEmpty && page.totalRows > 0) {
        _offset = 0;
        _loadEvidence();
        return;
      }

      setState(() {
        _page = page;
        _loadingEvidence = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loadingEvidence = false;
        _evidenceError = 'Could not retrieve evidence records: $e';
      });
    }
  }

  void _onGroupChanged(String? group) {
    if (group == null || group == _selectedGroup) return;
    setState(() {
      _selectedGroup = group;
      final datasets = _groupedCatalog[group] ?? [];
      _selectedDataset = datasets.isNotEmpty ? datasets.first : null;
      _offset = 0;
      _search.clear();
      _page = null;
    });
    if (_selectedDataset != null) {
      _loadEvidence();
    }
  }

  void _onDatasetChanged(AuditCatalogItem? dataset) {
    if (dataset == null || dataset.key == _selectedDataset?.key) return;
    setState(() {
      _selectedDataset = dataset;
      _offset = 0;
      _search.clear();
      _page = null;
    });
    _loadEvidence();
  }

  void _resetFilters() {
    _search.clear();
    _offset = 0;
    _loadEvidence();
  }

  Future<void> _export() async {
    if (_selectedDataset == null || _exporting) return;
    setState(() => _exporting = true);

    try {
      await widget.service.exportEvidence(
        tenantId: _tenantId,
        dataset: _selectedDataset!.key,
        datasetLabel: _selectedDataset!.label,
        from: widget.from,
        to: widget.to,
        locationId: _locationId,
        query: _search.text.trim(),
      );
      if (mounted) {
        ThqNotify.success(
          context,
          'Exported ${_selectedDataset!.label} evidence successfully.',
        );
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.error(context, 'Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_catalogError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _catalogError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Loading Catalog'),
              ),
            ],
          ),
        ),
      );
    }

    final currentGroupDatasets = _groupedCatalog[_selectedGroup] ?? [];

    return Column(
      children: [
        // Top Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: LayoutBuilder(
            builder: (context, bounds) {
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Business Area Selector
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedGroup,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Business Area',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: _groupedCatalog.keys.map((group) {
                        final count = _groupedCatalog[group]?.length ?? 0;
                        return DropdownMenuItem(
                          value: group,
                          child: Text(
                            '$group ($count)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: _exporting ? null : _onGroupChanged,
                    ),
                  ),

                  // Dataset Selector
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<AuditCatalogItem>(
                      initialValue: _selectedDataset,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Evidence Dataset',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: currentGroupDatasets.map((d) {
                        return DropdownMenuItem(
                          value: d,
                          child: Text(
                            '${d.label}${d.isMaster ? ' (Master)' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: _exporting ? null : _onDatasetChanged,
                    ),
                  ),

                  // Search Field
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () {
                          _offset = 0;
                          _loadEvidence();
                        });
                      },
                      onSubmitted: (_) {
                        _offset = 0;
                        _loadEvidence();
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search reference, party, actor…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        suffixIcon: _search.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _search.clear();
                                  _offset = 0;
                                  _loadEvidence();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Date range / Period notice
                  if (_selectedDataset?.isMaster == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: const Text(
                        'Master records (current snapshot)',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _exporting ? null : widget.onPickPeriod,
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        '${auditDate(widget.from.toIso8601String().substring(0, 10))} – ${auditDate(widget.to.toIso8601String().substring(0, 10))}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),

                  // Refresh Button
                  IconButton(
                    tooltip: 'Refresh Evidence',
                    onPressed: _loadingEvidence || _exporting ? null : _loadEvidence,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),

                  // Reset Filters Button
                  if (_search.text.isNotEmpty || _offset > 0)
                    TextButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    ),

                  // Export Button
                  IconButton(
                    tooltip: 'Export Evidence to CSV',
                    onPressed: _loadingEvidence || _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 20),
                  ),
                ],
              );
            },
          ),
        ),

        // Scope & Period Basis Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${LocationScopeService.scopeLabel(widget.session)} · ${_page?.periodBasis ?? 'Authoritative verified evidence'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (_page?.sensitiveValuesVisible == true)
                Text(
                  'Sensitive records visible (Authorized auditor)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
        ),

        if (_loadingEvidence)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),

        // Error message if any
        if (_evidenceError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _evidenceError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                TextButton(onPressed: _loadEvidence, child: const Text('Retry')),
              ],
            ),
          ),

        // Records Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _loadingEvidence && _page == null
                ? const Center(child: CircularProgressIndicator())
                : _buildTable(),
          ),
        ),

        // Pager
        _buildPager(),
      ],
    );
  }

  Widget _buildTable() {
    final rows = _page?.rows ?? [];
    if (rows.isEmpty && !_loadingEvidence) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'No evidence records found for ${_selectedDataset?.label ?? 'this dataset'}.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try selecting a wider date range or clearing your search filter.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final tableRows = rows.map((r) => r.toJson()).toList(growable: false);

    return AuditTable(
      columns: const [
        AuditColumn('reference', 'Reference / Code', flex: 3),
        AuditColumn('date', 'Date', compact: false),
        AuditColumn('party', 'Party / Entity', flex: 3, compact: false),
        AuditColumn('status', 'Status'),
        AuditColumn('amount', 'Amount', numeric: true),
        AuditColumn('quantity', 'Qty', numeric: true, compact: false),
        AuditColumn('location', 'Location', compact: false),
        AuditColumn('actor', 'User', compact: false),
        AuditColumn('journal_count', 'Journals', numeric: true, compact: false),
      ],
      rows: tableRows,
      currency: widget.session.currencyCode,
      onOpen: (row) => _openRecord(row['id']?.toString() ?? ''),
      empty: 'No matching evidence records.',
    );
  }

  Widget _buildPager() {
    final total = _page?.totalRows ?? 0;
    final count = _page?.rows.length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 0
                  ? '0 records'
                  : '${_offset + 1}–${_offset + count} of $total records',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: _loadingEvidence || _offset == 0
                ? null
                : () {
                    setState(() {
                      _offset = (_offset - 50).clamp(0, total);
                    });
                    _loadEvidence();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: _loadingEvidence || _offset + count >= total
                ? null
                : () {
                    setState(() {
                      _offset += 50;
                    });
                    _loadEvidence();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _openRecord(String recordId) {
    if (_selectedDataset == null || recordId.isEmpty) return;
    showEvidenceRecordDetailDialog(
      context: context,
      service: widget.service,
      tenantId: _tenantId,
      dataset: _selectedDataset!.key,
      recordId: recordId,
      session: widget.session,
      from: widget.from,
      to: widget.to,
      locationId: _locationId,
    );
  }
}
