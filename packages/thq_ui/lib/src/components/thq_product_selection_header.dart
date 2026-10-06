import 'package:flutter/material.dart';

/// A constrained product header: selected quantities and tracking labels share
/// one flexible column, leaving the favorite action a full touch target.
class ThqProductSelectionHeader extends StatelessWidget {
  const ThqProductSelectionHeader({
    super.key,
    required this.icon,
    required this.favorite,
    required this.onFavorite,
    this.quantity,
    this.quantityDescription,
    this.tracking,
  });
  final IconData icon;
  final bool favorite;
  final VoidCallback onFavorite;
  final String? quantity, quantityDescription, tracking;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: colors.primary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quantity != null)
                Tooltip(
                  message:
                      quantityDescription ?? 'Selected quantity: $quantity',
                  child: Text(
                    quantity!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    semanticsLabel: quantityDescription,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (tracking != null)
                Text(
                  tracking!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: favorite ? 'Remove favorite' : 'Add favorite',
          onPressed: onFavorite,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          iconSize: 18,
          icon: Icon(
            favorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: favorite ? colors.secondary : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
