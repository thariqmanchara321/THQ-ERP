import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class PlatformAdminsScreen extends StatefulWidget {
  const PlatformAdminsScreen({super.key});
  @override
  State<PlatformAdminsScreen> createState() => _PlatformAdminsScreenState();
}

class _PlatformAdminsScreenState extends State<PlatformAdminsScreen> {
  final _service = PlatformConfigService();
  late Future<List<PlatformAdminInfo>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _service.getPlatformAdmins();
  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _grant() async {
    final username = TextEditingController();
    String role = 'support_admin';
    String? error;
    bool saving = false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Grant Platform Access'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The username must already belong to an authenticated THQ user. Flutter never receives the service-role key.',
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Platform role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'super_admin',
                      child: Text('Super Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'support_admin',
                      child: Text('Support Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'billing_admin',
                      child: Text('Billing Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'sales_admin',
                      child: Text('Sales Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'technical_admin',
                      child: Text('Technical Admin'),
                    ),
                    DropdownMenuItem(value: 'auditor', child: Text('Auditor')),
                  ],
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v != null) setDialogState(() => role = v);
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
                      if (username.text.trim().length < 4) {
                        setDialogState(() => error = 'Username is required.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _service.grantPlatformAdmin(
                          username: username.text,
                          roleKey: role,
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
              child: Text(saving ? 'Saving...' : 'Grant'),
            ),
          ],
        ),
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  Future<void> _revoke(PlatformAdminInfo admin) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text('Remove platform access for @${admin.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.revokePlatformAdmin(admin.userId);
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text('Platform Admins'),
        actions: const [AdminHomeButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _grant,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Grant Access'),
      ),
      body: FutureBuilder<List<PlatformAdminInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                const Text(
                  'Platform Administrators',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Separate platform responsibilities instead of granting every employee unrestricted Super Admin access.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                ...rows.map(
                  (a) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.admin_panel_settings_outlined),
                      ),
                      title: Text(
                        '@${a.username}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(a.roleKey.replaceAll('_', ' ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!a.active) const Chip(label: Text('Disabled')),
                          IconButton(
                            tooltip: 'Revoke',
                            onPressed: () => _revoke(a),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
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
