import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/support_service.dart';

class SupportScreen extends StatefulWidget {
  final ClientSession session;
  final String appKey;

  const SupportScreen({super.key, required this.session, this.appKey = 'pos'});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final SupportService _service = SupportService();
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String _category = 'general';
  String _priority = 'normal';
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject and description are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _service.createTicket(
        tenantId: widget.session.business.id,
        locationId: widget.session.device?.locationId,
        deviceId: widget.session.device?.deviceId,
        appKey: widget.appKey,
        appVersion: ThqReleaseContract.appVersion,
        category: _category,
        priority: _priority,
        subject: _subject.text,
        description: _description.text,
      );
      if (!mounted) return;
      final number = result['ticket_number']?.toString() ?? 'Support ticket';
      _subject.clear();
      _description.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$number created.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Support Centre',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Report an issue with business, store, device and user context attached automatically.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _contextChip(
                              Icons.business_outlined,
                              widget.session.business.name,
                            ),
                            _contextChip(
                              Icons.store_outlined,
                              widget.session.device?.locationCode ??
                                  'No device',
                            ),
                            _contextChip(
                              Icons.computer_outlined,
                              widget.session.device?.deviceCode ??
                                  widget.appKey,
                            ),
                            _contextChip(
                              Icons.person_outline,
                              widget.session.username,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _subject,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            prefixIcon: Icon(Icons.subject),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _category,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'general',
                                    child: Text('General'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'billing',
                                    child: Text('Billing'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'inventory',
                                    child: Text('Inventory'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'printing',
                                    child: Text('Printing'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'login',
                                    child: Text('Login / Access'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'error',
                                    child: Text('Error / Crash'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _category = v ?? 'general'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _priority,
                                decoration: const InputDecoration(
                                  labelText: 'Priority',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'low',
                                    child: Text('Low'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'normal',
                                    child: Text('Normal'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'high',
                                    child: Text('High'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'urgent',
                                    child: Text('Urgent'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _priority = v ?? 'normal'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _description,
                          minLines: 5,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: 'Describe what happened',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _submit,
                            icon: const Icon(Icons.send_outlined),
                            label: Text(
                              _saving ? 'Sending…' : 'Send Support Request',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contextChip(IconData icon, String value) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(value.isEmpty ? 'Unknown' : value),
  );
}
