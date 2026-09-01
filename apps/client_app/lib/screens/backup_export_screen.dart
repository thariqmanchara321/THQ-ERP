import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client_session.dart';
import '../services/backup_service.dart';

class BackupExportScreen extends StatefulWidget {
  final ClientSession session;
  const BackupExportScreen({super.key, required this.session});

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  final BackupService _service = BackupService();
  bool _loading = false;
  String? _backup;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.createBackupJson(
        tenantId: widget.session.business.id,
      );
      if (mounted) setState(() => _backup = data);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final data = _backup;
    if (data == null) return;
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup JSON copied. Save it as a .json file in a secure location.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup & Export',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Generate a portable business snapshot containing master data, transactions, stock, accounting and audit metadata.',
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _generate,
                icon: const Icon(Icons.backup_outlined),
                label: Text(_loading ? 'Generating…' : 'Generate Backup'),
              ),
              if (_backup != null)
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Backup JSON'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (_backup == null && !_loading)
            const Expanded(
              child: Center(
                child: Text('No backup generated in this session.'),
              ),
            )
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup ready • ${(_backup!.length / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'For production deployments, keep this export together with Supabase-managed database backups. The JSON intentionally excludes device secrets.',
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SelectionArea(
                          child: SingleChildScrollView(
                            child: Text(
                              _backup!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
