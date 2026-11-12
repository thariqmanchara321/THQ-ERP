import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../foundations/thq_tokens.dart';
import '../components/thq_buttons.dart';

/// Interactive side-by-side comparison view presenting existing THQ product records
/// against external intelligence candidates (e.g. GS1 Registry or Open Food Facts).
///
/// Ensures:
/// 1. Zero automatic overwrites: User must explicitly review and approve changes.
/// 2. Conflict highlighting: Inconsistencies between THQ and external data are clearly surfaced.
/// 3. Invariant protection: Financial prices, tax rates, and inventory stock quantities are strictly locked.
/// 4. Provenance display: Source attribution and confidence are displayed transparently.
class ThqCatalogueComparisonView extends StatefulWidget {
  final CatalogueComparison comparison;
  final ValueChanged<Map<String, String?>> onApplyEnrichment;
  final VoidCallback? onDiscard;
  final VoidCallback? onCreateNewDraft;
  final String approvedByUserId;

  const ThqCatalogueComparisonView({
    super.key,
    required this.comparison,
    required this.onApplyEnrichment,
    this.onDiscard,
    this.onCreateNewDraft,
    this.approvedByUserId = 'admin',
  });

  @override
  State<ThqCatalogueComparisonView> createState() => _ThqCatalogueComparisonViewState();
}

class _ThqCatalogueComparisonViewState extends State<ThqCatalogueComparisonView> {
  late final CatalogueComparison _comparison;

  @override
  void initState() {
    super.initState();
    _comparison = widget.comparison;
  }

  void _toggleField(String fieldKey, bool value) {
    setState(() {
      _comparison.setFieldAccepted(fieldKey, value);
    });
  }

  void _selectAllNonConflicting() {
    setState(() {
      for (final f in _comparison.fields) {
        if (!f.isProtected && !f.isConflict && f.externalValue != null && f.externalValue!.trim().isNotEmpty) {
          f.isAccepted = true;
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final f in _comparison.fields) {
        if (!f.isProtected && f.externalValue != null && f.externalValue!.trim().isNotEmpty) {
          f.isAccepted = true;
        }
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (final f in _comparison.fields) {
        if (!f.isProtected) {
          f.isAccepted = false;
        }
      }
    });
  }

  void _applyChanges() {
    final payload = _comparison.buildEnrichmentPayload();
    widget.onApplyEnrichment(payload);
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _comparison.candidate;
    final acceptedCount = _comparison.acceptedFieldsCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(ThqTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card: Discovered Product & Source Attribution
          _buildHeaderCard(context, candidate),
          const SizedBox(height: ThqTokens.space12),

          // Conflict & Safety Information Banners
          _buildAlertBanners(context),
          const SizedBox(height: ThqTokens.space12),

          // Quick Selection Toolbar
          _buildSelectionToolbar(context),
          const SizedBox(height: ThqTokens.space12),

          // Side-by-Side Comparison Table
          _buildComparisonTable(context),
          const SizedBox(height: ThqTokens.space16),

          // Additional Specifications Card (if any)
          if (candidate.specifications.isNotEmpty) ...[
            _buildSpecCard(context, candidate),
            const SizedBox(height: ThqTokens.space16),
          ],

          // Action Buttons
          _buildActionFooter(context, acceptedCount),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, ExternalProductCandidate candidate) {
    final theme = Theme.of(context);
    final isGs1 = candidate.isGs1Verified;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        side: BorderSide(
          color: isGs1 ? Colors.blue.withAlpha(120) : theme.dividerColor.withAlpha(80),
          width: isGs1 ? 1.5 : 1,
        ),
      ),
      color: isGs1 ? Colors.blue.withAlpha(15) : theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(ThqTokens.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image or Icon
            ClipRRect(
              borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
              child: Container(
                width: 72,
                height: 72,
                color: theme.colorScheme.surfaceContainerHighest,
                child: candidate.imageUrl != null && candidate.imageUrl!.isNotEmpty
                    ? Image.network(
                        candidate.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Icon(
                          Icons.inventory_2_outlined,
                          size: 32,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.inventory_2_outlined,
                        size: 32,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
            ),
            const SizedBox(width: ThqTokens.space16),

            // Title, Barcode & Source Attribution
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Source Provider Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isGs1 ? Colors.blue.shade700 : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(ThqTokens.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isGs1 ? Icons.verified : Icons.cloud_done_outlined,
                              size: 13,
                              color: isGs1 ? Colors.white : theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              candidate.sourceName,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isGs1 ? Colors.white : theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Match Confidence Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(30),
                          borderRadius: BorderRadius.circular(ThqTokens.radiusPill),
                          border: Border.all(color: Colors.green.withAlpha(100)),
                        ),
                        child: Text(
                          '${(candidate.matchConfidence * 100).toInt()}% Match',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    candidate.productName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 15, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'GTIN / Barcode: ${candidate.barcode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (candidate.brand != null && candidate.brand!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Text(
                          '•  Brand: ${candidate.brand}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBanners(BuildContext context) {
    final theme = Theme.of(context);
    final hasConflicts = _comparison.hasConflicts;
    final conflictCount = _comparison.conflictCount;

    return Column(
      children: [
        if (hasConflicts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(25),
              borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
              border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber.shade900),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$conflictCount conflicting field(s) detected. Existing catalogue values will be preserved unless explicitly checked.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
              border: Border.all(color: Colors.green.shade600.withAlpha(90)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No direct data conflicts found. Review discovered attributes and choose fields to enrich your catalogue.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),

        // Invariant Accounting Protection Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
            border: Border.all(color: theme.dividerColor.withAlpha(60)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Protected Accounting Invariant: Selling price, cost price, tax rate, and stock balances cannot be altered by external catalogue data.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionToolbar(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Field Approval:',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        TextButton.icon(
          onPressed: _selectAllNonConflicting,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Non-Conflicting'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
        TextButton(
          onPressed: _selectAll,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Select All'),
        ),
        TextButton(
          onPressed: _deselectAll,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Clear All'),
        ),
      ],
    );
  }

  Widget _buildComparisonTable(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        side: BorderSide(color: theme.dividerColor.withAlpha(90)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Row
          Container(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 140,
                  child: Text('Catalogue Field', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Current THQ Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('External Suggestion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                const SizedBox(
                  width: 80,
                  child: Text('Accept', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Field Rows
          for (int i = 0; i < _comparison.fields.length; i++) ...[
            _buildFieldRow(context, _comparison.fields[i]),
            if (i < _comparison.fields.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldRow(BuildContext context, CatalogueComparisonField field) {
    final theme = Theme.of(context);
    final isProtected = field.isProtected;
    final isConflict = field.isConflict;
    final hasExternal = field.externalValue != null && field.externalValue!.trim().isNotEmpty;

    Color rowColor = Colors.transparent;
    if (isConflict) {
      rowColor = Colors.amber.withAlpha(18);
    } else if (field.isAccepted) {
      rowColor = Colors.green.withAlpha(12);
    }

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Field Label & Conflict Badge
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  field.fieldLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isConflict)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'CONFLICT',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  )
                else if (isProtected)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade700,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'PROTECTED',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Current Value
          Expanded(
            child: Text(
              field.currentValue != null && field.currentValue!.trim().isNotEmpty
                  ? field.currentValue!
                  : '— (Empty)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: field.currentValue != null && field.currentValue!.trim().isNotEmpty
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withAlpha(130),
                fontStyle: field.currentValue == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // External Suggestion
          Expanded(
            child: isProtected
                ? Row(
                    children: [
                      Icon(Icons.lock, size: 13, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'Ledger Invariant',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                : Text(
                    hasExternal ? field.externalValue! : '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasExternal ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isConflict ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Accept Action Checkbox / Lock Icon
          SizedBox(
            width: 80,
            child: Center(
              child: isProtected
                  ? Tooltip(
                      message: 'Protected accounting invariant',
                      child: Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                    )
                  : Checkbox(
                      value: field.isAccepted,
                      onChanged: hasExternal ? (v) => _toggleField(field.fieldKey, v ?? false) : null,
                      visualDensity: VisualDensity.compact,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecCard(BuildContext context, ExternalProductCandidate candidate) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        side: BorderSide(color: theme.dividerColor.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ThqTokens.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Additional Specifications Discovered',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: candidate.specifications.entries.map((entry) {
                return Chip(
                  label: Text('${entry.key}: ${entry.value}'),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
                  labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionFooter(BuildContext context, int acceptedCount) {
    final isExisting = _comparison.isExistingProduct;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (widget.onDiscard != null)
              ThqSecondaryButton(
                label: 'Discard',
                icon: Icons.close,
                onPressed: widget.onDiscard,
              ),
            if (widget.onCreateNewDraft != null && isExisting)
              ThqSecondaryButton(
                label: 'Create As New Draft',
                icon: Icons.add_box_outlined,
                onPressed: widget.onCreateNewDraft,
              ),
          ],
        ),

        // Primary Approval Button
        ThqPrimaryButton(
          label: isExisting
              ? 'Enrich Product ($acceptedCount Selected)'
              : 'Create Product Draft ($acceptedCount Selected)',
          icon: Icons.auto_awesome,
          onPressed: acceptedCount > 0 ? _applyChanges : null,
        ),
      ],
    );
  }
}
