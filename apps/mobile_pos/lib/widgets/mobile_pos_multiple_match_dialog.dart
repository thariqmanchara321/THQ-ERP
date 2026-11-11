import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

/// Modal dialog presented when a scanned barcode or SKU in Mobile POS
/// resolves to multiple candidate product variants.
///
/// Requires the cashier to make an explicit disambiguation selection,
/// preventing silent misattribution of inventory lines.
class MobilePosMultipleMatchDialog extends StatelessWidget {
  final String rawCode;
  final List<ProductIdentificationMatch> matches;
  final String currencyCode;

  const MobilePosMultipleMatchDialog({
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
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
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
                          'Scanned: $rawCode',
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
              const Text(
                'This barcode maps to multiple variants. Tap the exact item to add to bill:',
                style: TextStyle(fontSize: 12),
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
              const SizedBox(height: 12),
              ThqSecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(null),
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
    final currencySymbol = currencyCode == 'INR' ? '₹' : '$currencyCode ';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (match.variantName.isNotEmpty &&
                            match.variantName != match.productName)
                          _tag(
                            'Variant: ${match.variantName}',
                            scheme.primary,
                            scheme.primaryContainer,
                          ),
                        _tag(
                          'SKU: ${match.sku}',
                          scheme.onSurfaceVariant,
                          scheme.surfaceContainerHighest,
                        ),
                        _tag(
                          'Stock: ${match.stockQuantity.toStringAsFixed(1)} ${match.unitCode}',
                          match.stockQuantity > 0 ? Colors.green : Colors.red,
                          (match.stockQuantity > 0 ? Colors.green : Colors.red)
                              .withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$currencySymbol${match.sellingPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: ThqPrimaryButton(
                      label: 'Select',
                      onPressed: onSelected,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textCol,
        ),
      ),
    );
  }
}
