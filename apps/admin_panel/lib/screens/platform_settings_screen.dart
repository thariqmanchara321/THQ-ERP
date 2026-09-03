import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  final _service = PlatformConfigService();
  late Future<List<PlatformSetting>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _service.getSettings();
  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  String _display(dynamic value) {
    if (value is String) return value;
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  dynamic _parse(String text, dynamic original) {
    if (original is bool) return text.trim().toLowerCase() == 'true';
    if (original is num) return num.tryParse(text.trim()) ?? original;
    if (original is Map || original is List) return jsonDecode(text);
    return text;
  }

  Future<void> _edit(PlatformSetting setting) async {
    final controller = TextEditingController(text: _display(setting.value));
    String? error;
    bool saving = false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(setting.key),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((setting.description ?? '').isNotEmpty)
                  Text(setting.description!),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Value',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
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
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _service.setSetting(
                          setting.key,
                          _parse(controller.text, setting.value),
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
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text('Platform Settings'),
        actions: const [AdminHomeButton()],
      ),
      body: FutureBuilder<List<PlatformSetting>>(
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
                  'Platform Settings',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Global defaults only. Tenant-specific business settings continue to override these values.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                ...rows.map(
                  (s) => Card(
                    child: ListTile(
                      title: Text(
                        s.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${s.description ?? ''}\n${_display(s.value)}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        onPressed: () => _edit(s),
                        icon: const Icon(Icons.edit_outlined),
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
