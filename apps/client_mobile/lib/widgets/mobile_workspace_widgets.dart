import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/mobile_session.dart';

String workspaceMoney(MobileSession session, dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return '${session.currencyCode} ${NumberFormat('#,##0.00').format(number)}';
}

String workspaceNumber(dynamic value, {int decimals = 0}) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  final suffix = decimals <= 0
      ? ''
      : '.${List<String>.filled(decimals, '0').join()}';
  return NumberFormat('#,##0$suffix').format(number);
}

String workspaceDate(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  return parsed == null
      ? raw
      : DateFormat('dd MMM yyyy').format(parsed.toLocal());
}

String workspaceDateTime(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  return parsed == null
      ? raw
      : DateFormat('dd MMM yyyy • hh:mm a').format(parsed.toLocal());
}

String workspaceLabel(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

class WorkspaceHero extends StatelessWidget {
  final MobileSession session;
  final String locationLabel;
  final String netSales;
  final String grossProfit;
  final String invoices;
  final String approvals;
  final VoidCallback onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback onRefresh;

  const WorkspaceHero({
    super.key,
    required this.session,
    required this.locationLabel,
    required this.netSales,
    required this.grossProfit,
    required this.invoices,
    required this.approvals,
    required this.onSearch,
    required this.onNotifications,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.secondary],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  'T',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THQ BUSINESS',
                      style: TextStyle(
                        color: scheme.onPrimary.withValues(alpha: .8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.35,
                      ),
                    ),
                  ],
                ),
              ),
              ThqAppearanceButton(foregroundColor: scheme.onPrimary),
              _HeroIconButton(
                tooltip: 'Search business',
                icon: Icons.search_rounded,
                onPressed: onSearch,
              ),
              if (onNotifications != null) ...[
                const SizedBox(width: 5),
                _HeroIconButton(
                  tooltip: 'Notifications',
                  icon: Icons.notifications_none_rounded,
                  onPressed: onNotifications!,
                ),
              ],
              const SizedBox(width: 5),
              _HeroIconButton(
                tooltip: 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.store_mall_directory_outlined,
                color: scheme.onPrimary.withValues(alpha: .8),
                size: 15,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: .8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                session.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: .8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(label: 'Net sales', value: netSales),
                    ),
                    _HeroDivider(),
                    Expanded(
                      child: _HeroMetric(
                        label: 'Gross profit',
                        value: grossProfit,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(label: 'Invoices', value: invoices),
                    ),
                    _HeroDivider(),
                    Expanded(
                      child: _HeroMetric(label: 'Approvals', value: approvals),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceQuickAction extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const WorkspaceQuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceRecordCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? status;
  final String? trailing;
  final List<WorkspaceRecordField> fields;
  final VoidCallback? onTap;
  final Widget? footer;

  const WorkspaceRecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.trailing,
    this.fields = const [],
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '—' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null && status!.isNotEmpty) ...[
                const SizedBox(width: 8),
                ThqMobileStatusChip(label: status!),
              ],
            ],
          ),
          if (trailing != null && trailing!.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              trailing!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 7,
              children: fields
                  .where((field) => field.value.isNotEmpty)
                  .map((field) => _RecordFieldView(field: field))
                  .toList(),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class WorkspaceRecordField {
  final String label;
  final String value;
  final IconData? icon;

  const WorkspaceRecordField(this.label, this.value, {this.icon});
}

class WorkspaceErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const WorkspaceErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => ThqMobileEmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'Could not load this view',
    message: error.toString(),
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Retry'),
    ),
  );
}

class WorkspaceLoadingList extends StatelessWidget {
  final int count;

  const WorkspaceLoadingList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 14,
                width: 150,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                width: 210,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _HeroIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.13),
    ),
    icon: Icon(icon, size: 20),
  );
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.18),
  );
}

class _RecordFieldView extends StatelessWidget {
  final WorkspaceRecordField field;

  const _RecordFieldView({required this.field});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (field.icon != null) ...[
          Icon(field.icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Text(
          '${field.label}: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        Text(
          field.value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
