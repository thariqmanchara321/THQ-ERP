import 'package:flutter/material.dart';

import '../services/platform_config_service.dart';
import '../widgets/admin_home_button.dart';

class PlatformSupportScreen extends StatefulWidget {
  const PlatformSupportScreen({super.key});
  @override
  State<PlatformSupportScreen> createState() => _PlatformSupportScreenState();
}

class _PlatformSupportScreenState extends State<PlatformSupportScreen> {
  final PlatformConfigService _service = PlatformConfigService();
  String _status = 'open';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
      final rows = await _service.getSupportTickets(
        status: _status == 'all' ? null : _status,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    await _service.setSupportTicketStatus(row['id'].toString(), status);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Support Centre'),
      leading: const AdminHomeButton(),
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Support Tickets',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const Text(
            'Business issues arrive with tenant/device/application context.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children:
                [
                      'open',
                      'in_progress',
                      'waiting_customer',
                      'resolved',
                      'closed',
                      'all',
                    ]
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s.replaceAll('_', ' ').toUpperCase()),
                        selected: _status == s,
                        onSelected: (_) {
                          setState(() => _status = s);
                          _load();
                        },
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _rows.isEmpty
                ? const Center(child: Text('No support tickets in this view.'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                child: Text(
                                  (row['priority']?.toString() ?? 'N')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${row['ticket_number']} • ${row['subject']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '${row['business_name']} • ${row['location_code']} • ${row['device_code']} • ${row['app_key']} ${row['app_version'] ?? ''}',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      row['description']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: row['status']?.toString(),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'open',
                                    child: Text('Open'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'in_progress',
                                    child: Text('In Progress'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'waiting_customer',
                                    child: Text('Waiting'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'resolved',
                                    child: Text('Resolved'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'closed',
                                    child: Text('Closed'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) _setStatus(row, v);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
