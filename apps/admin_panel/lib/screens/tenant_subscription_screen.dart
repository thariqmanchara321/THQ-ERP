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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Tenant Subscription'),
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
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: SizedBox(
                width: 760,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.businessName,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _Info('Plan', current.planName ?? 'No plan assigned'),
                        _Info('Status', current.status),
                        _Info('Billing cycle', current.billingCycle),
                        _Info('Plan key', current.planKey ?? '-'),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: () => _edit(current, plans),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Manage Subscription'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
