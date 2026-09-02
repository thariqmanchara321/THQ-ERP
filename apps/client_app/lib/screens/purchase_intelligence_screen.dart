import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';

class PurchaseIntelligenceScreen extends StatefulWidget {
  final ClientSession session;
  const PurchaseIntelligenceScreen({super.key, required this.session});

  @override
  State<PurchaseIntelligenceScreen> createState() =>
      _PurchaseIntelligenceScreenState();
}

class _PurchaseIntelligenceScreenState extends State<PurchaseIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _quotations = const [];
  List<Map<String, dynamic>> _performance = const [];
  List<Map<String, dynamic>> _reorder = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final result = await Future.wait([
        db.rpc(
          'purchase_quotations_list_v500',
          params: {'p_tenant_id': widget.session.business.id, 'p_query': ''},
        ),
        db.rpc(
          'supplier_performance_v500',
          params: {'p_tenant_id': widget.session.business.id, 'p_limit': 500},
        ),
        db.rpc(
          'reorder_suggestions_v500',
          params: {
            'p_tenant_id': widget.session.business.id,
            'p_days': 30,
            'p_query': '',
            'p_limit': 1000,
          },
        ),
      ]);
      _quotations = _rows(result[0]);
      _performance = _rows(result[1]);
      _reorder = _rows(result[2]);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Purchase Intelligence'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabs: const [
          Tab(text: 'Quotations'),
          Tab(text: 'Supplier Performance'),
          Tab(text: 'Reorder Suggestions'),
        ],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          )
        : TabBarView(
            controller: _tabs,
            children: [
              _list(
                _quotations,
                titleKeys: const ['quotation_number', 'supplier_name'],
                detailKeys: const [
                  'status',
                  'quote_date',
                  'valid_until',
                  'grand_total',
                  'request_number',
                ],
              ),
              _list(
                _performance,
                titleKeys: const ['supplier_name'],
                detailKeys: const [
                  'purchase_value',
                  'po_count',
                  'grn_count',
                  'damage_reject_pct',
                  'on_time_pct',
                  'avg_delivery_days',
                ],
              ),
              _list(
                _reorder,
                titleKeys: const ['product_name', 'sku'],
                detailKeys: const [
                  'location_name',
                  'current_stock',
                  'reorder_level',
                  'suggested_reorder',
                  'suggested_supplier_name',
                  'last_unit_cost',
                ],
              ),
            ],
          ),
  );

  Widget _list(
    List<Map<String, dynamic>> rows, {
    required List<String> titleKeys,
    required List<String> detailKeys,
  }) {
    if (rows.isEmpty) return const Center(child: Text('No data available.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = rows[i];
        final title = titleKeys
            .map((k) => r[k])
            .where((v) => v != null && '$v'.isNotEmpty)
            .join(' • ');
        final detail = detailKeys
            .where((k) => r[k] != null)
            .map((k) => '${k.replaceAll('_', ' ')}: ${r[k]}')
            .join(' • ');
        return ListTile(
          dense: true,
          title: Text(title.isEmpty ? 'Record' : title),
          subtitle: Text(detail),
        );
      },
    );
  }
}
