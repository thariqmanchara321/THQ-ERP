import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

/// Modal dialog presented when a scanned barcode or SKU resolves to multiple
/// product variants, requiring explicit cashier disambiguation.
class PosMultipleMatchDialog extends StatelessWidget {
  final String rawCode;
  final List<ProductIdentificationMatch> matches;
  final String currencyCode;

  const PosMultipleMatchDialog({
    super.key,
    required this.rawCode,
    required this.matches,
    required this.currencyCode,
  });

  String _formatMoney(double amount) {
    final formatted = amount.toStringAsFixed(2);
    return currencyCode == 'INR' ? '₹$formatted' : '$currencyCode $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.call_split, color: Colors.amber, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Multiple Variants Found (${matches.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanned code "$rawCode" matched multiple product variants. Select the intended variant to add to the cart:',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: matches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final match = matches[index];
                  final variantDisplay = match.variantName.isNotEmpty
                      ? match.variantName
                      : 'Default Variant';

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    title: Text(
                      match.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      'Variant: $variantDisplay • SKU: ${match.sku} • Stock: ${match.stockQuantity} ${match.unitCode}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatMoney(match.sellingPrice),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ThqPrimaryButton(
                          label: 'Select',
                          onPressed: () => Navigator.of(context).pop(match),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        ThqSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }
}

