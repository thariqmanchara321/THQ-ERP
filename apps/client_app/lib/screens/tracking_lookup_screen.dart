import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';

class TrackingLookupScreen extends StatefulWidget {
  final ClientSession session;

  const TrackingLookupScreen({super.key, required this.session});

  @override
  State<TrackingLookupScreen> createState() => _TrackingLookupScreenState();
}

class _TrackingLookupScreenState extends State<TrackingLookupScreen> {
  final TextEditingController _code = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _search() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final response = await Supabase.instance.client.rpc(
        'entity_tracking_lookup',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_tracking_code': code,
        },
      );

      if (!mounted) {
        return;
      }

      if (response == null) {
        setState(() => _error = 'No entity found with that tracking code.');
      } else if (response is Map) {
        setState(() => _result = Map<String, dynamic>.from(response));
      } else {
        setState(() => _error = 'Unexpected tracking lookup response.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Tracking ID Lookup')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Find any tracked ERP record',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Search human-readable codes such as PRD-, LOC-, CUS-, SUP-, '
                  'PURR-, SALR- or EXPR-. The UUID remains the canonical ID.',
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                          labelText: 'Tracking code',
                          hintText: 'Example: SALR-00000001',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.qr_code_2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _search,
                        icon: const Icon(Icons.search),
                        label: Text(_loading ? 'Searching...' : 'Search'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_result!['entity_type'] ?? 'Entity')
                                .toString()
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            'Tracking: ${_result!['tracking_code'] ?? '-'}',
                          ),
                          const SizedBox(height: 6),
                          SelectableText('UUID: ${_result!['id'] ?? '-'}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
