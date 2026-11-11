import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../models/mobile_session.dart';

/// Modal dialog presented when a scanned code in Client Mobile resolves
/// to multiple candidate products or variants.
class MobileSmartInventoryMultipleMatchDialog extends StatelessWidget {
  final String rawCode;
  final List<ProductIdentificationMatch> matches;
  final String currencyCode;

  const MobileSmartInventoryMultipleMatchDialog({
    super.key,
    required this.rawCode,
    required this.matches,
    this.currencyCode = 'INR',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: scheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.call_split_rounded,
                      color: Colors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Multiple Variants Found (${matches.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Code: $rawCode',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'This barcode maps to multiple variants. Select the intended item:',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    return _CandidateCard(
                      match: match,
                      currencyCode: currencyCode,
                      onSelected: () => Navigator.of(context).pop(match),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final ProductIdentificationMatch match;
  final String currencyCode;
  final VoidCallback onSelected;

  const _CandidateCard({
    required this.match,
    required this.currencyCode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.productName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (match.variantName.isNotEmpty &&
                            match.variantName != match.productName)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              match.variantName,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$currencyCode ${match.sellingPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (match.sku.isNotEmpty)
                          _InfoChip(label: 'SKU: ${match.sku}'),
                        if (match.barcode != null &&
                            match.barcode!.isNotEmpty)
                          _InfoChip(label: 'BC: ${match.barcode}'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Stock: ${match.stockQuantity} ${match.unitCode}',
                    style: TextStyle(
                      fontSize: 11,
                      color: match.stockQuantity > 0
                          ? const Color(0xFF00875A)
                          : scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Dialog allowing manual typing or paste of barcodes, SKUs, or internal codes.
class MobileManualCodeEntryDialog extends StatefulWidget {
  final String? initialCode;

  const MobileManualCodeEntryDialog({super.key, this.initialCode});

  @override
  State<MobileManualCodeEntryDialog> createState() =>
      _MobileManualCodeEntryDialogState();
}

class _MobileManualCodeEntryDialogState
    extends State<MobileManualCodeEntryDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.keyboard_outlined, size: 22),
          SizedBox(width: 8),
          Text('Enter Product Code', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type or paste any Barcode, SKU, QR string, or Part Number:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'e.g. 8901030382910, SKU-401...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.qr_code_rounded),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _controller.clear()),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _controller.text.trim().isNotEmpty ? _submit : null,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Lookup'),
        ),
      ],
    );
  }
}

/// Bottom modal sheet presenting comprehensive details of an identified product.
///
/// Cost price is strictly guarded: only shown if the user is an owner or has
/// the 'inventory.manage' permission.
class MobileProductDetailModal extends StatelessWidget {
  final ProductIdentificationMatch match;
  final MobileSession session;

  const MobileProductDetailModal({
    super.key,
    required this.match,
    required this.session,
  });

  bool get _canViewCostPrice =>
      session.isOwner || session.hasPermission('inventory.manage');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.productName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (match.variantName.isNotEmpty &&
                        match.variantName != match.productName)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          match.variantName,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Match pill & Identification details
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0052CC).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Method: ${match.matchMethod.name}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0052CC),
                  ),
                ),
              ),
              if (match.matchedCode.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Matched: ${match.matchedCode}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Attributes Grid
          _buildInfoRow('SKU', match.sku.isNotEmpty ? match.sku : 'None'),
          if (match.barcode != null && match.barcode!.isNotEmpty)
            _buildInfoRow('Barcode', match.barcode!),
          _buildInfoRow('Unit of Measure', match.unitCode),
          _buildInfoRow(
            'Current Stock',
            '${match.stockQuantity} ${match.unitCode}',
            valueColor: match.stockQuantity > 0
                ? const Color(0xFF00875A)
                : scheme.error,
            isBold: true,
          ),
          _buildInfoRow(
            'Selling Price',
            '${session.currency} ${match.sellingPrice.toStringAsFixed(2)}',
            isBold: true,
          ),

          // Guarded Cost Price
          if (_canViewCostPrice)
            _buildInfoRow(
              'Cost Price',
              match.costPrice != null
                  ? '${session.currency} ${match.costPrice!.toStringAsFixed(2)}'
                  : 'N/A',
              valueColor: const Color(0xFF4A5568),
            )
          else
            _buildInfoRow(
              'Cost Price',
              'Restricted (Requires inventory.manage permission)',
              valueColor: scheme.outline,
            ),

          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value,
      {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
