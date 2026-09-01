import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../services/platform_config_service.dart';
import '../widgets/admin_home_button.dart';

class AppVersionsScreen extends StatefulWidget {
  const AppVersionsScreen({super.key});

  @override
  State<AppVersionsScreen> createState() => _AppVersionsScreenState();
}

class _AppVersionsScreenState extends State<AppVersionsScreen> {
  final PlatformConfigService _service = PlatformConfigService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _releases = const [];
  List<Map<String, dynamic>> _devices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.getAppReleases(),
        _service.getDeviceVersions(),
      ]);
      if (!mounted) return;
      setState(() {
        _releases = result[0];
        _devices = result[1];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRelease() async {
    final version = TextEditingController(text: ThqReleaseContract.appVersion);
    final notes = TextEditingController();
    final url = TextEditingController();
    String app = 'client';
    String platform = 'windows';
    String status = 'stable';
    int build = ThqReleaseContract.buildNumber;
    bool minimum = false;
    bool mandatory = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add App Release'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: app,
                          decoration: const InputDecoration(labelText: 'App'),
                          items: const [
                            DropdownMenuItem(
                              value: 'client',
                              child: Text('Client ERP'),
                            ),
                            DropdownMenuItem(value: 'pos', child: Text('POS')),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Admin'),
                            ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => app = v ?? 'client'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: platform,
                          decoration: const InputDecoration(
                            labelText: 'Platform',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'windows',
                              child: Text('Windows'),
                            ),
                            DropdownMenuItem(
                              value: 'android',
                              child: Text('Android'),
                            ),
                            DropdownMenuItem(value: 'web', child: Text('Web')),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => platform = v ?? 'windows'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: version,
                    decoration: const InputDecoration(labelText: 'Version'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: '$build',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Build number',
                    ),
                    onChanged: (v) => build = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'beta', child: Text('Beta')),
                      DropdownMenuItem(value: 'stable', child: Text('Stable')),
                      DropdownMenuItem(
                        value: 'deprecated',
                        child: Text('Deprecated'),
                      ),
                      DropdownMenuItem(
                        value: 'blocked',
                        child: Text('Blocked'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => status = v ?? 'stable'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: minimum,
                    title: const Text('Minimum supported version'),
                    onChanged: (v) =>
                        setDialogState(() => minimum = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: mandatory,
                    title: const Text('Mandatory update'),
                    onChanged: (v) =>
                        setDialogState(() => mandatory = v ?? false),
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Release notes',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(
                      labelText: 'Download URL (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final versionText = version.text.trim();
    final notesText = notes.text.trim();
    final urlText = url.text.trim();
    version.dispose();
    notes.dispose();
    url.dispose();
    if (ok != true || versionText.isEmpty) return;
    await _service.saveAppRelease(
      appKey: app,
      platform: platform,
      version: versionText,
      buildNumber: build,
      status: status,
      minimumSupported: minimum,
      mandatory: mandatory,
      releaseNotes: notesText,
      downloadUrl: urlText,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Versions'),
        leading: const AdminHomeButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Release Management',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'See installed versions and publish update policy.',
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Running Admin: v${ThqReleaseContract.appVersion} • Build ${ThqReleaseContract.buildNumber} • migration ${ThqReleaseContract.minimumMigration}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: _addRelease,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Release'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _panel(
                            'Published Releases',
                            _releases
                                .map(
                                  (r) =>
                                      '${r['app_key']} • ${r['platform']} • ${r['version']} (${r['status']})${r['mandatory'] == true ? ' • REQUIRED' : ''}',
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _panel(
                            'Installed Devices',
                            _devices
                                .map(
                                  (d) =>
                                      '${d['business_name']} • ${d['location_code']} • ${d['device_code']}\n${d['app_key']} ${d['version'] ?? 'unknown'} • ${d['platform'] ?? ''}',
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _panel(String title, List<String> rows) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No records yet.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) =>
                        ListTile(dense: true, title: Text(rows[i])),
                  ),
          ),
        ],
      ),
    ),
  );
}
