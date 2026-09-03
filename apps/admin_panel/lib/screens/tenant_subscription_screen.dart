import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class TenantSubscriptionScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;
  const TenantSubscriptionScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });
  @override
  State<TenantSubscriptionScreen> createState() =>
      _TenantSubscriptionScreenState();
}

class _TenantSubscriptionScreenState extends State<TenantSubscriptionScreen> {
  final _service = PlatformConfigService();
  late Future<(TenantSubscriptionInfo, List<SubscriptionPlan>)> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();
  Future<(TenantSubscriptionInfo, List<SubscriptionPlan>)> _load() async => (
    await _service.getTenantSubscription(widget.tenantId),
    await _service.getPlans(),
  );

  Future<void> _edit(
    TenantSubscriptionInfo current,
    List<SubscriptionPlan> plans,
  ) async {
    String? planId = current.planId ?? (plans.isEmpty ? null : plans.first.id);
    String status = current.status == 'none' ? 'trial' : current.status;
    String cycle = current.billingCycle;
    String? error;
    bool saving = false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Subscription • ${widget.businessName}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: planId,
                  decoration: const InputDecoration(
                    labelText: 'Plan',
                    border: OutlineInputBorder(),
                  ),
                  items: plans
                      .where((p) => p.isActive)
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) => setDialogState(() => planId = v),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'trial', child: Text('Trial')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'past_due',
                      child: Text('Past due'),
                    ),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v != null) setDialogState(() => status = v);
                        },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: cycle,
                  decoration: const InputDecoration(
                    labelText: 'Billing cycle',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v != null) setDialogState(() => cycle = v);
                        },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (planId == null) {
                        setDialogState(() => error = 'Choose a plan.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _service.setTenantSubscription(
                          tenantId: widget.tenantId,
                          planId: planId!,
                          status: status,
                          billingCycle: cycle,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString();
                        });
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text(
          'Tenant Subscription',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
      ),
      body: FutureBuilder<(TenantSubscriptionInfo, List<SubscriptionPlan>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final data = snapshot.data!;
          final current = data.$1;
          final plans = data.$2;

          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 25,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Plan assignment, status and billing cycle',
                              style: TextStyle(
                                fontSize: 7.7,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _edit(current, plans),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Manage'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Info(
                              'Plan',
                              current.planName ?? 'No plan assigned',
                            ),
                            _Info('Status', current.status),
                            _Info('Billing cycle', current.billingCycle),
                            _Info('Plan key', current.planKey ?? '-'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label, value;
  const _Info(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 7.8, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
