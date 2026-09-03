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
    final scheme = Theme.of(context).colorScheme;

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
                      const Text(
                        'Tracking ID Lookup',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Find any tracked ERP record by human-readable code',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
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
                                prefixIcon: Icon(Icons.qr_code_2, size: 17),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          SizedBox(
                            height: 36,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _search,
                              icon: const Icon(Icons.search, size: 15),
                              label: Text(_loading ? 'Searching...' : 'Search'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 8.5,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (_result!['entity_type'] ?? 'Entity')
                                  .toString()
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              'Tracking: '
                              '${_result!['tracking_code'] ?? '-'}',
                              style: const TextStyle(fontSize: 8.5),
                            ),
                            const SizedBox(height: 3),
                            SelectableText(
                              'UUID: ${_result!['id'] ?? '-'}',
                              style: const TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      ),
                    ],
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
