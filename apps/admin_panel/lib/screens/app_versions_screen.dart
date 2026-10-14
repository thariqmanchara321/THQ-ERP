import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

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
  List<Map<String, dynamic>> _updateLogs = const [];

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
        _service.getAppUpdateLogs(),
      ]);
      if (!mounted) return;
      setState(() {
        _releases = result[0];
        _devices = result[1];
        _updateLogs = result[2];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setReleaseStatus(String id, String status) async {
    try {
      await _service.setAppReleaseStatus(id, status);
      await _load();
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Release status updated to $status.')),
      );
    } catch (e) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _addRelease() async {
    final version = TextEditingController(text: ThqReleaseContract.appVersion);
    final notes = TextEditingController();
    final url = TextEditingController();
    final sha256Ctrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final minVersionCtrl = TextEditingController(text: '5.1.0');
    final publisherCtrl = TextEditingController(text: 'THQ Systems');

    String app = 'client';
    String platform = 'windows';
    String channel = 'stable';
    String status = 'stable';
    int build = ThqReleaseContract.buildNumber;
    bool minimum = false;
    bool mandatory = false;

    final ok = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add App Release'),
          content: SizedBox(
            width: 620,
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
                            DropdownMenuItem(value: 'client', child: Text('Client ERP (THQ Business)')),
                            DropdownMenuItem(value: 'pos', child: Text('POS PC (THQ POS)')),
                            DropdownMenuItem(value: 'admin', child: Text('Admin Panel')),
                          ],
                          onChanged: (v) => setDialogState(() => app = v ?? 'client'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: platform,
                          decoration: const InputDecoration(labelText: 'Platform'),
                          items: const [
                            DropdownMenuItem(value: 'windows', child: Text('Windows')),
                            DropdownMenuItem(value: 'android', child: Text('Android')),
                            DropdownMenuItem(value: 'web', child: Text('Web')),
                          ],
                          onChanged: (v) => setDialogState(() => platform = v ?? 'windows'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: channel,
                          decoration: const InputDecoration(labelText: 'Channel'),
                          items: const [
                            DropdownMenuItem(value: 'stable', child: Text('Stable')),
                            DropdownMenuItem(value: 'beta', child: Text('Beta / Testing')),
                          ],
                          onChanged: (v) => setDialogState(() => channel = v ?? 'stable'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'stable', child: Text('Stable')),
                            DropdownMenuItem(value: 'beta', child: Text('Beta')),
                            DropdownMenuItem(value: 'paused', child: Text('Paused')),
                            DropdownMenuItem(value: 'deprecated', child: Text('Deprecated')),
                            DropdownMenuItem(value: 'revoked', child: Text('Revoked')),
                          ],
                          onChanged: (v) => setDialogState(() => status = v ?? 'stable'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: version,
                          decoration: const InputDecoration(
                            labelText: 'Version (e.g. 8.2.0)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$build',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Build number'),
                          onChanged: (v) => build = int.tryParse(v) ?? 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(
                      labelText: 'Download URL (HTTPS setup installer)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sizeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Package size (bytes)',
                            hintText: 'e.g. 48234496',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: minVersionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Min supported version',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sha256Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'SHA-256 Checksum (64 hex characters)',
                      hintText: 'e.g. 5a1b... or leave blank for optional check',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: publisherCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Publisher / Subject Signature',
                      hintText: 'e.g. THQ Systems',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: minimum,
                          title: const Text('Minimum supported', style: TextStyle(fontSize: 12)),
                          onChanged: (v) => setDialogState(() => minimum = v ?? false),
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: mandatory,
                          title: const Text('Mandatory update', style: TextStyle(fontSize: 12)),
                          onChanged: (v) => setDialogState(() => mandatory = v ?? false),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Release notes',
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
              child: const Text('Save & Publish'),
            ),
          ],
        ),
      ),
    );

    final versionText = version.text.trim();
    final notesText = notes.text.trim();
    final urlText = url.text.trim();
    final sha256Text = sha256Ctrl.text.trim();
    final pkgSize = int.tryParse(sizeCtrl.text.trim()) ?? 0;
    final minVerText = minVersionCtrl.text.trim();
    final pubText = publisherCtrl.text.trim();

    version.dispose();
    notes.dispose();
    url.dispose();
    sha256Ctrl.dispose();
    sizeCtrl.dispose();
    minVersionCtrl.dispose();
    publisherCtrl.dispose();

    if (ok != true || versionText.isEmpty) return;

    await _service.saveAppRelease(
      appKey: app,
      platform: platform,
      channel: channel,
      version: versionText,
      buildNumber: build,
      status: status,
      minimumSupported: minimum,
      mandatory: mandatory,
      releaseNotes: notesText,
      downloadUrl: urlText,
      packageSizeBytes: pkgSize,
      sha256Checksum: sha256Text.isNotEmpty ? sha256Text : null,
      publisherSignature: pubText.isNotEmpty ? pubText : null,
      minSupportedVersion: minVerText.isNotEmpty ? minVerText : null,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text(
          'App Versions & Release Management',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        leading: const AdminHomeButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Padding(
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
                              const Text(
                                'Release Management & Updater Telemetry',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Admin v${ThqReleaseContract.appVersion} | '
                                'Build ${ThqReleaseContract.buildNumber} | '
                                'Migration ${ThqReleaseContract.minimumMigration}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          visualDensity: VisualDensity.compact,
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                        ),
                        const SizedBox(width: 3),
                        FilledButton.icon(
                          onPressed: _addRelease,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Release'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 980;

                        final releasesPanel = _releasesPanel();
                        final devicesPanel = _devicesPanel();
                        final telemetryPanel = _telemetryPanel();

                        if (stacked) {
                          return DefaultTabController(
                            length: 3,
                            child: Column(
                              children: [
                                const TabBar(
                                  tabs: [
                                    Tab(text: 'Releases'),
                                    Tab(text: 'Installed Devices'),
                                    Tab(text: 'Update Logs'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      releasesPanel,
                                      devicesPanel,
                                      telemetryPanel,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Row(
                          children: [
                            Expanded(flex: 4, child: releasesPanel),
                            const SizedBox(width: 5),
                            Expanded(flex: 3, child: devicesPanel),
                            const SizedBox(width: 5),
                            Expanded(flex: 3, child: telemetryPanel),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _releasesPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Published Releases',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_releases.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _releases.isEmpty
                ? const Center(child: Text('No releases published yet.'))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _releases.length,
                    itemBuilder: (_, i) {
                      final r = _releases[i];
                      final id = r['id']?.toString() ?? '';
                      final status = r['status']?.toString() ?? 'stable';
                      final channel = r['channel']?.toString() ?? 'stable';
                      final appKey = r['app_key']?.toString() ?? '';
                      final platform = r['platform']?.toString() ?? '';
                      final version = r['version']?.toString() ?? '';
                      final build = r['build_number']?.toString() ?? '';
                      final notes = r['release_notes']?.toString() ?? '';
                      final url = r['download_url']?.toString() ?? '';

                      Color badgeColor = Colors.teal;
                      if (status == 'paused') badgeColor = Colors.amber;
                      if (status == 'revoked') badgeColor = Colors.red;
                      if (status == 'beta') badgeColor = Colors.blue;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '$appKey ($platform) — v$version (b$build)',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          channel,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (url.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, color: scheme.primary),
                                    ),
                                  ],
                                  if (notes.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      notes,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 16),
                              padding: EdgeInsets.zero,
                              tooltip: 'Actions',
                              onSelected: (val) => _setReleaseStatus(id, val),
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'stable', child: Text('Set Stable')),
                                const PopupMenuItem(value: 'beta', child: Text('Set Beta')),
                                const PopupMenuItem(value: 'paused', child: Text('Pause Release')),
                                const PopupMenuItem(value: 'revoked', child: Text('Revoke Release')),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _devicesPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Installed Devices',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_devices.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('No devices registered.'))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _devices.length,
                    itemBuilder: (_, i) {
                      final d = _devices[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${d['business_name']} | ${d['location_code']} | ${d['device_code']}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${d['app_key']} v${d['version'] ?? 'unknown'} | ${d['platform'] ?? ''}',
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Update Telemetry & Error Logs',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_updateLogs.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _updateLogs.isEmpty
                ? const Center(child: Text('No update activity recorded yet.'))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _updateLogs.length,
                    itemBuilder: (_, i) {
                      final log = _updateLogs[i];
                      final status = log['status']?.toString() ?? '';
                      final appKey = log['app_key']?.toString() ?? '';
                      final fromVer = log['from_version']?.toString() ?? '';
                      final toVer = log['to_version']?.toString() ?? '';
                      final err = log['error_message']?.toString() ?? '';
                      final ts = log['created_at']?.toString() ?? '';

                      Color statusColor = Colors.blue;
                      if (status == 'installed') statusColor = Colors.green;
                      if (status == 'failed') statusColor = Colors.red;
                      if (status == 'installing') statusColor = Colors.amber;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$appKey: $fromVer -> $toVer',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (err.isNotEmpty)
                              Text(
                                err,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: Colors.red),
                              ),
                            Text(
                              ts,
                              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
