import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/global_search_service.dart';
import 'product_detail_screen.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  final ClientSession session;
  final String initialQuery;
  const GlobalSearchScreen({
    super.key,
    required this.session,
    this.initialQuery = '',
  });

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  late final TextEditingController _controller;
  final _service = GlobalSearchService();
  Timer? _debounce;
  List<GlobalSearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _search(widget.initialQuery),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.search(
        tenantId: widget.session.business.id,
        query: value,
      );
      if (mounted) setState(() => _results = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String type) => switch (type) {
    'product' => Icons.inventory_2_outlined,
    'customer' => Icons.person_outline,
    'supplier' => Icons.local_shipping_outlined,
    'sale' => Icons.receipt_long_outlined,
    'purchase' => Icons.shopping_cart_outlined,
    'account' => Icons.account_balance_outlined,
    'stock_transfer' => Icons.swap_horiz_outlined,
    'task' => Icons.task_alt_outlined,
    'workshop_job' => Icons.build_outlined,
    _ => Icons.search,
  };

  Future<void> _open(GlobalSearchResult item) async {
    if (item.entityType == 'product') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            session: widget.session,
            variantId: item.entityId,
          ),
        ),
      );
    } else if (item.entityType == 'sale') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SaleDetailScreen(session: widget.session, saleId: item.entityId),
        ),
      );
    } else if (item.entityType == 'purchase') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PurchaseDetailScreen(
            session: widget.session,
            purchaseId: item.entityId,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.title} • ${item.publicId.isEmpty ? item.entityType : item.publicId}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search THQ Business')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _changed,
                  decoration: InputDecoration(
                    hintText:
                        'Search product, SKU, customer, supplier, invoice or tracking ID…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              setState(() => _results = const []);
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Text(
                            _controller.text.trim().isEmpty
                                ? 'Type anything to search across this business.'
                                : 'No matching records.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            return Card(
                              child: ListTile(
                                onTap: () => _open(item),
                                leading: CircleAvatar(
                                  child: Icon(_icon(item.entityType)),
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (item.publicId.isNotEmpty) item.publicId,
                                    if (item.subtitle.isNotEmpty) item.subtitle,
                                    item.entityType.toUpperCase(),
                                  ].join(' • '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
