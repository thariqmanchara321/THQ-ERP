import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/client_session.dart';
import '../../services/location_scope_service.dart';
import 'audit_intelligence_service.dart';
import 'audit_widgets.dart';
import 'evidence_detail_dialog.dart';
import 'models/audit_integrity_models.dart';

/// Interactive workspace for Business & Financial Integrity Checks.
///
/// Provides an investigative, read-only analysis of discrepancies across accounting,
/// inventory, sales, purchases, banking, tax and system operations.
class IntegrityReconciliationView extends StatefulWidget {
  const IntegrityReconciliationView({
    super.key,
    required this.session,
    required this.service,
    required this.from,
    required this.to,
    required this.onPickPeriod,
    this.onOpenEvidenceExplorer,
  });

  final ClientSession session;
  final AuditIntelligenceService service;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickPeriod;
  final void Function(String dataset, String? query)? onOpenEvidenceExplorer;

  @override
  State<IntegrityReconciliationView> createState() =>
      _IntegrityReconciliationViewState();
}

class _IntegrityReconciliationViewState
    extends State<IntegrityReconciliationView> {
  final _search = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  AuditIntegrityResult? _result;

  String _selectedCategory = 'all';
  String _statusFilter = '';
  String _severityFilter = '';

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);
  String get _currency => widget.session.currencyCode;

  static const _categories = {
    'all': 'All checks',
    'accounting': 'Accounting',
    'inventory': 'Inventory',
    'sales_purchase': 'Sales & Purchases',
    'banking_payment': 'Banking & Payments',
    'tax_gst': 'Tax & GST',
    'operational': 'Operational & Security',
  };

  @override
  void initState() {
    super.initState();
    _loadChecks();
  }

  @override
  void didUpdateWidget(covariant IntegrityReconciliationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _loadChecks();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadChecks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.service.integrityChecks(
        tenantId: _tenantId,
        from: widget.from,
        to: widget.to,
        locationId: _locationId,
      );

      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not evaluate integrity checks: $e';
      });
    }
  }

  List<AuditIntegrityCheck> get _filteredChecks {
    if (_result == null) return const [];
    var list = _result!.byCategory(_selectedCategory);

    if (_statusFilter.isNotEmpty) {
      final sf = _statusFilter.toLowerCase();
      list = list.where((c) {
        if (sf == 'issue') return c.isIssueDetected;
        if (sf == 'review') return c.isNeedsReview;
        if (sf == 'passed') return c.isPassed;
        if (sf == 'insufficient') return c.isInsufficientData;
        return c.status.toLowerCase() == sf;
      }).toList();
    }

    if (_severityFilter.isNotEmpty) {
      list = list
          .where((c) => c.severity == _severityFilter.toLowerCase())
          .toList();
    }

    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.title.toLowerCase().contains(q) ||
            c.reference.toLowerCase().contains(q) ||
            c.basis.toLowerCase().contains(q) ||
            c.explanation.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  void _showCheckDetails(AuditIntegrityCheck check) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _CheckDetailDialog(
        session: widget.session,
        service: widget.service,
        check: check,
        from: widget.from,
        to: widget.to,
        locationId: _locationId,
        currency: _currency,
        onOpenEvidenceExplorer: widget.onOpenEvidenceExplorer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopSummaryBar(),
        _buildCategoryTabs(),
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildTopSummaryBar() {
    final res = _result;
    final total = res?.totalCount ?? 0;
    final issues = res?.issueCount ?? 0;
    final reviews = res?.reviewCount ?? 0;
    final passed = res?.passedCount ?? 0;
    final insufficient = res?.insufficientDataCount ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _summaryCard(
            label: 'Total Checks',
            value: total.toString(),
            color: Colors.blueGrey,
            icon: Icons.fact_check_outlined,
          ),
          _summaryCard(
            label: 'Issues Detected',
            value: issues.toString(),
            color: issues > 0 ? Colors.red : Colors.grey,
            icon: Icons.error_outline,
            isWarning: issues > 0,
          ),
          _summaryCard(
            label: 'Needs Review',
            value: reviews.toString(),
            color: reviews > 0 ? Colors.orange : Colors.grey,
            icon: Icons.warning_amber_rounded,
          ),
          _summaryCard(
            label: 'Passed',
            value: passed.toString(),
            color: Colors.green,
            icon: Icons.check_circle_outline,
          ),
          if (insufficient > 0)
            _summaryCard(
              label: 'Insufficient Data',
              value: insufficient.toString(),
              color: Colors.blueGrey.shade400,
              icon: Icons.help_outline,
            ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    bool isWarning = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isWarning ? 0.6 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final entry = _categories.entries.elementAt(index);
          final key = entry.key;
          final label = entry.value;
          final isSelected = _selectedCategory == key;

          final count = key == 'all'
              ? _result?.totalCount ?? 0
              : _result?.byCategory(key).length ?? 0;

          final categoryIssues = _result
                  ?.byCategory(key)
                  .where((c) => c.isIssueDetected)
                  .length ??
              0;

          return Center(
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: categoryIssues > 0
                          ? Colors.red.withValues(alpha: 0.2)
                          : isSelected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.15)
                          : Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: categoryIssues > 0
                            ? Colors.red.shade700
                            : isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = key);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: (constraints.maxWidth * 0.3).clamp(160, 320),
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      setState(() {});
                    });
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search checks, rules, basis…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
              _buildDropdown(
                label: 'Status',
                value: _statusFilter,
                width: 150,
                items: const {
                  '': 'All statuses',
                  'issue': 'Issues only',
                  'review': 'Needs review',
                  'passed': 'Passed',
                  'insufficient': 'Insufficient data',
                },
                onChanged: (v) => setState(() => _statusFilter = v),
              ),
              _buildDropdown(
                label: 'Severity',
                value: _severityFilter,
                width: 140,
                items: const {
                  '': 'All severities',
                  'critical': 'Critical',
                  'high': 'High',
                  'medium': 'Medium',
                  'low': 'Low',
                  'informational': 'Informational',
                },
                onChanged: (v) => setState(() => _severityFilter = v),
              ),
              OutlinedButton.icon(
                onPressed: widget.onPickPeriod,
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(
                  '${_formatDate(widget.from)} – ${_formatDate(widget.to)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: 'Refresh checks',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadChecks,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required double width,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        items: items.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _result == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Evaluating authoritative integrity checks…'),
          ],
        ),
      );
    }

    if (_error != null && _result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadChecks,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Evaluation'),
              ),
            ],
          ),
        ),
      );
    }

    final checks = _filteredChecks;
    if (checks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 56,
                color: Colors.green.shade600,
              ),
              const SizedBox(height: 16),
              const Text(
                'No integrity issues found matching current filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'All evaluated checks in this category are consistent with underlying business rules.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: checks.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemBuilder: (context, index) {
        final check = checks[index];
        return _buildCheckCard(check);
      },
    );
  }

  Widget _buildCheckCard(AuditIntegrityCheck check) {
    Color statusColor;
    IconData statusIcon;

    if (check.isPassed) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (check.isIssueDetected) {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else if (check.isNeedsReview) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning_amber;
    } else if (check.isInsufficientData) {
      statusColor = Colors.blueGrey;
      statusIcon = Icons.help_outline;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.info_outline;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: check.isIssueDetected
              ? Colors.red.withValues(alpha: 0.4)
              : check.isNeedsReview
              ? Colors.orange.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showCheckDetails(check),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _categoryBadge(check.category),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            check.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        _severityBadge(check.severity),
                        const SizedBox(width: 8),
                        _statusChip(check.status, statusColor),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      check.explanation.isNotEmpty
                          ? check.explanation
                          : check.basis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (check.count > 0 ||
                        (check.difference != null &&
                            check.difference!.abs() > 0.005)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (check.count > 0)
                            Text(
                              'Affected records: ${check.count}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: check.isIssueDetected
                                    ? Colors.red.shade700
                                    : null,
                              ),
                            ),
                          if (check.count > 0 && check.difference != null)
                            const Text(
                              ' · ',
                              style: TextStyle(color: Colors.grey),
                            ),
                          if (check.difference != null &&
                              check.difference!.abs() > 0.005)
                            Text(
                              'Discrepancy: ${auditMoney(check.difference, _currency)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: check.isIssueDetected
                                    ? Colors.red.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryBadge(String category) {
    final label = _categories[category] ?? category;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _severityBadge(String severity) {
    Color col;
    switch (severity.toLowerCase()) {
      case 'critical':
        col = Colors.red.shade800;
        break;
      case 'high':
        col = Colors.deepOrange;
        break;
      case 'medium':
        col = Colors.amber.shade900;
        break;
      case 'low':
        col = Colors.blueGrey;
        break;
      default:
        col = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: col.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: col,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// Detailed drill-down dialog for an individual integrity check.
class _CheckDetailDialog extends StatefulWidget {
  const _CheckDetailDialog({
    required this.session,
    required this.service,
    required this.check,
    required this.from,
    required this.to,
    this.locationId,
    required this.currency,
    this.onOpenEvidenceExplorer,
  });

  final ClientSession session;
  final AuditIntelligenceService service;
  final AuditIntegrityCheck check;
  final DateTime from;
  final DateTime to;
  final String? locationId;
  final String currency;
  final void Function(String dataset, String? query)? onOpenEvidenceExplorer;

  @override
  State<_CheckDetailDialog> createState() => _CheckDetailDialogState();
}

class _CheckDetailDialogState extends State<_CheckDetailDialog> {
  bool _loading = false;
  String? _error;
  AuditCheckDrilldownResult? _drilldown;

  @override
  void initState() {
    super.initState();
    _loadDrilldown();
  }

  Future<void> _loadDrilldown() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.service.checkDrilldownRecords(
        tenantId: widget.session.business.id,
        checkId: widget.check.id,
        from: widget.from,
        to: widget.to,
        locationId: widget.locationId,
        limit: 50,
      );

      if (!mounted) return;
      setState(() {
        _drilldown = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load affected records: $e';
      });
    }
  }

  void _inspectRecord(AuditCheckDrilldownRecord record) {
    showEvidenceRecordDetailDialog(
      context: context,
      service: widget.service,
      tenantId: widget.session.business.id,
      dataset: record.dataset.isNotEmpty
          ? record.dataset
          : (widget.check.dataset ?? 'audit'),
      recordId: record.id,
      session: widget.session,
      from: widget.from,
      to: widget.to,
      locationId: widget.locationId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.check;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950, maxHeight: 720),
        child: Column(
          children: [
            ListTile(
              dense: true,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _statusBadge(c.status),
                ],
              ),
              subtitle: Text(
                'Category: ${c.category.toUpperCase()} · Reference: ${c.reference} · Read-only investigation',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRuleExplanationCard(c),
                    const SizedBox(height: 16),
                    _buildMetricsCard(c),
                    const SizedBox(height: 16),
                    _buildAffectedRecordsSection(c),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (c.dataset != null &&
                      widget.onOpenEvidenceExplorer != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.travel_explore, size: 16),
                      label: Text('Open Dataset (${c.dataset}) in Explorer'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenEvidenceExplorer!(c.dataset!, null);
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleExplanationCard(AuditIntegrityCheck c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.rule_folder_outlined, size: 16, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Expected Business Rule & Methodology',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.basis, style: const TextStyle(fontSize: 12)),
          if (c.explanation.isNotEmpty && c.explanation != c.basis) ...[
            const SizedBox(height: 8),
            Text(
              c.explanation,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsCard(AuditIntegrityCheck c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _metricItem('Affected Records', c.count.toString()),
          if (c.expected != null)
            _metricItem(
              'Expected Value',
              auditMoney(c.expected, widget.currency),
            ),
          if (c.actual != null)
            _metricItem(
              'Actual Value',
              auditMoney(c.actual, widget.currency),
            ),
          if (c.difference != null && c.difference!.abs() > 0.005)
            _metricItem(
              'Total Variance',
              auditMoney(c.difference, widget.currency),
              color: c.isIssueDetected ? Colors.red : Colors.orange,
            ),
          if (c.verifiedChains != null)
            _metricItem(
              'Verified Hash Chains',
              c.verifiedChains.toString(),
              color: Colors.green,
            ),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAffectedRecordsSection(AuditIntegrityCheck c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt, size: 16),
            const SizedBox(width: 8),
            Text(
              'Affected Source Records (${_drilldown?.records.length ?? 0})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading && _drilldown == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          )
        else if (_drilldown == null || _drilldown!.records.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No individual failing records detected for this check in the selected period and store scope.',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.0),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(3.0),
                4: FixedColumnWidth(130),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Reference',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Date',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Variance',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Discrepancy Details',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Evidence Action',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final rec in _drilldown!.records)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          rec.reference,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          rec.date ?? '—',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          rec.difference != null
                              ? auditMoney(
                                  auditNumber(rec.difference),
                                  widget.currency,
                                )
                              : '—',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          rec.description,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          icon: const Icon(Icons.visibility, size: 12),
                          label: const Text(
                            'Inspect',
                            style: TextStyle(fontSize: 10),
                          ),
                          onPressed: () => _inspectRecord(rec),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color col;
    if (status.toLowerCase() == 'passed') {
      col = Colors.green;
    } else if (status.toLowerCase() == 'issue detected' ||
        status.toLowerCase() == 'high risk') {
      col = Colors.red;
    } else if (status.toLowerCase() == 'needs review') {
      col = Colors.orange;
    } else {
      col = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: col),
      ),
    );
  }
}
