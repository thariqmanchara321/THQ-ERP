import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uuid/uuid.dart';
import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_kot_service.dart';
import '../services/mobile_pos_auth_service.dart';
import '../services/mobile_pos_local_store.dart';
import '../services/mobile_pricing_service.dart';
import '../services/mobile_pos_sync_service.dart';
import '../services/mobile_receipt_service.dart';
import 'barcode_scanner_screen.dart';
import 'mobile_pos_entry_screen.dart';
import 'offline_queue_screen.dart';

class MobilePosHomeScreen extends StatefulWidget {
  final PosSession session;
  const MobilePosHomeScreen({super.key, required this.session});
  @override
  State<MobilePosHomeScreen> createState() => _State();
}

class _State extends State<MobilePosHomeScreen> {
  final local = MobilePosLocalStore.instance,
      sync = MobilePosSyncService(),
      receipt = MobileReceiptService(),
      kot = MobileKotService(),
      pricing = MobilePricingService();
  final search = TextEditingController();
  final cart = <CartLine>[];
  List<MobileProduct> products = [];
  List<MobileCustomer> customers = [];
  MobileCustomer? customer;
  bool loading = true, syncing = false;
  double roundOff = 0;
  String syncText = 'Starting...';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _start();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => _heartbeat());
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await local.db;
    try {
      await sync.refreshCatalogue(widget.session);
      syncText = 'Online | cache refreshed';
    } catch (e) {
      syncText = 'Offline | using local cache';
    }
    await _reload();
    if (mounted) setState(() => loading = false);
    _heartbeat();
  }

  Future<void> _reload() async {
    products = await local.products(
      widget.session.tenantId,
      widget.session.locationId,
    );
    customers = await local.customers(widget.session.tenantId);
    customer = customer ?? _walkIn(customers);
    if (mounted) setState(() {});
  }

  MobileCustomer? _walkIn(List<MobileCustomer> rows) {
    for (final c in rows) {
      if (c.isWalkIn) return c;
    }
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _heartbeat() async {
    if (syncing) return;
    syncing = true;
    try {
      final r = await sync.sync(widget.session);
      if (r.synced > 0) {
        await _reload();
      }
      if (mounted)
        setState(
          () => syncText = r.conflicts > 0
              ? '${r.conflicts} conflict(s) need attention'
              : r.pending > 0
              ? 'Offline | invoices queued'
              : 'Synced',
        );
    } catch (_) {
      if (mounted)
        setState(() => syncText = 'Offline â€¢ invoices stay queued');
    } finally {
      syncing = false;
    }
  }

  List<MobileProduct> get filtered {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return products.take(100).toList();
    return products
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q) ||
              p.searchCodes.toLowerCase().contains(q),
        )
        .take(100)
        .toList();
  }

  double get beforeRoundOff => cart.fold(0, (s, x) => s + x.total);
  double get total => beforeRoundOff + roundOff;
  void applyRoundOff() {
    final d = beforeRoundOff.roundToDouble() - beforeRoundOff;
    setState(
      () => roundOff = d.abs() < 0.000001
          ? 0
          : double.parse(d.toStringAsFixed(2)),
    );
  }

  String money(double v) =>
      '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  Future<void> _resolvePrice(CartLine line, {bool notify = false}) async {
    try {
      final r = await pricing.resolve(
        session: widget.session,
        variantId: line.product.variantId,
        customerId: customer?.id,
        unitId: line.unit.unitId,
        quantity: line.quantity,
      );
      final price = numberValue(r['unit_price']);
      if (price <= 0) throw Exception('Resolved price is invalid.');
      if (!mounted || !cart.contains(line)) return;
      setState(() {
        line.resolvedUnitPrice = price;
        line.pricingSource =
            r['source_label']?.toString() ??
            r['source']?.toString() ??
            'pricing engine';
      });
    } catch (e) {
      line.resolvedUnitPrice = null;
      line.pricingSource = 'cached';
      if (notify && mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Live pricing unavailable; cached price kept: $e'),
          ),
        );
    }
  }

  Future<void> _resolveAllPrices({bool notify = false}) async {
    await Future.wait(cart.map((x) => _resolvePrice(x, notify: notify)));
  }

  Future<void> scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final serial = await local.findSerial(
      widget.session.tenantId,
      widget.session.locationId,
      code,
    );
    if (!mounted) return;
    if (serial != null) {
      final id = serial['variant_id']?.toString();
      MobileProduct? p;
      for (final x in products) {
        if (x.variantId == id) {
          p = x;
          break;
        }
      }
      if (p != null) {
        _add(p, serial: code);
        return;
      }
    }
    final matches = products.where((p) => p.matchesCode(code)).toList();
    if (matches.length == 1) {
      await _addProduct(matches.first);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            matches.isEmpty
                ? 'No cached product/serial matches $code.'
                : 'Multiple products match this code. Search and select one.',
          ),
        ),
      );
    }
  }

  Future<void> _addProduct(MobileProduct p) async {
    if (p.trackingMode == 'serial') {
      final ctrl = TextEditingController();
      final serial = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${p.name} serial'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Serial number'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (serial == null || serial.isEmpty) return;
      final found = await local.findSerial(
        widget.session.tenantId,
        widget.session.locationId,
        serial,
      );
      if (found == null || found['variant_id']?.toString() != p.variantId) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Serial is not available in the local cache.'),
            ),
          );
        return;
      }
      if (!mounted) return;
      _add(p, serial: serial);
      return;
    }
    _add(p);
  }

  void _add(MobileProduct p, {String? serial}) {
    final unit = p.defaultUnit;
    final step = unit.quantityStep > 0 ? unit.quantityStep : 1.0;
    if (p.itemType == 'stock' &&
        p.stockQuantity + 0.000001 < step * unit.conversionToBase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No offline stock available.')),
      );
      return;
    }
    if (serial != null && cart.any((l) => l.serialNumbers.contains(serial))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Serial already added.')));
      return;
    }
    if (serial == null && p.trackingMode != 'serial') {
      for (final l in cart) {
        if (l.product.variantId == p.variantId && l.unit.code == unit.code) {
          final next = l.quantity + step;
          if (p.itemType == 'stock' &&
              next * l.unit.conversionToBase > p.stockQuantity + 0.000001) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Not enough offline stock.')),
            );
            return;
          }
          setState(() => l.quantity = next);
          unawaited(_resolvePrice(l));
          return;
        }
      }
    }
    final line = CartLine(
      product: p,
      unit: unit,
      quantity: serial == null ? step : 1,
      serialNumbers: serial == null ? null : [serial],
    );
    setState(() => cart.add(line));
    unawaited(_resolvePrice(line));
  }

  void _qty(CartLine line, double delta) {
    if (line.product.trackingMode == 'serial') return;
    final step = line.unit.quantityStep > 0 ? line.unit.quantityStep : 1.0;
    final next = line.quantity + (delta.sign * step);
    if (next <= 0) {
      setState(() => cart.remove(line));
    } else if (line.product.itemType != 'stock' ||
        next * line.unit.conversionToBase <=
            line.product.stockQuantity + 0.000001) {
      setState(() => line.quantity = next);
      unawaited(_resolvePrice(line));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough offline stock.')),
      );
    }
  }

  Future<void> _chooseUnit(CartLine line) async {
    if (line.product.trackingMode == 'serial' ||
        line.product.saleUnits.length < 2)
      return;
    final chosen = await showDialog<MobileSaleUnit>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Billing unit | ${line.product.name}'),
        children: line.product.saleUnits
            .map(
              (u) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, u),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${u.name} (${u.code})'),
                  subtitle: Text(
                    '1 ${u.code} = ${u.conversionToBase} ${line.product.baseUnitCode}',
                  ),
                  trailing: Text(
                    money(
                      u.salePrice > 0 ? u.salePrice : line.product.sellingPrice,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    var qty = line.quantity;
    if (qty < chosen.quantityStep ||
        chosen.quantityStep > 0 &&
            (qty / chosen.quantityStep - (qty / chosen.quantityStep).round())
                    .abs() >
                0.000001)
      qty = chosen.quantityStep > 0 ? chosen.quantityStep : 1;
    if (line.product.itemType == 'stock' &&
        qty * chosen.conversionToBase > line.product.stockQuantity + 0.000001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough offline stock for this unit.'),
        ),
      );
      return;
    }
    setState(() {
      line.unit = chosen;
      line.quantity = qty;
      line.resolvedUnitPrice = null;
    });
    unawaited(_resolvePrice(line));
  }

  Future<void> chooseCustomer() async {
    final q = TextEditingController();
    var visible = customers;
    final selected = await showDialog<MobileCustomer>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Customer'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: q,
                  onChanged: (v) => setLocal(
                    () => visible = customers
                        .where(
                          (x) =>
                              x.name.toLowerCase().contains(v.toLowerCase()) ||
                              x.phone.contains(v),
                        )
                        .toList(),
                  ),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search customer',
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(visible[i].name),
                      subtitle: Text(visible[i].phone),
                      onTap: () => Navigator.pop(c, visible[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    q.dispose();
    if (selected != null && mounted) {
      setState(() => customer = selected);
      unawaited(_resolveAllPrices());
    }
  }

  Future<void> checkout() async {
    if (cart.isEmpty) return;
    if (customer == null) {
      await chooseCustomer();
      if (customer == null || !mounted) return;
    }
    await _resolveAllPrices();
    if (!mounted) return;
    final result = await showDialog<_PaymentResult>(
      context: context,
      builder: (_) => _PaymentDialog(
        total: total,
        currency: widget.session.currencyCode,
        allowCredit: customer?.isWalkIn != true,
      ),
    );
    if (result == null) return;
    final request = const Uuid().v4();
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'customer_id': customer!.id,
      'customer_name': customer!.name,
      'sale_date': DateFormat('yyyy-MM-dd').format(now),
      'sale_time': now.toIso8601String(),
      'due_date': result.paid + 0.005 < total
          ? DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 30)))
          : null,
      'items': cart.map((x) => x.toPayload()).toList(),
      'additional_charges': 0,
      'round_off': roundOff,
      'initial_payment': result.paid,
      'payment_method': result.method,
      'payment_reference': result.reference,
      'notes': 'Mobile POS',
      'total': total,
      'outstanding': (total - result.paid).clamp(0, double.infinity),
    };
    String localNo;
    try {
      localNo = await local.queueSale(
        requestId: request,
        tenantId: widget.session.tenantId,
        locationId: widget.session.locationId,
        deviceId: widget.session.deviceId,
        payload: payload,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save local invoice: $e')),
        );
      return;
    }
    var synced = false;
    try {
      final r = await sync.sync(widget.session, only: request);
      synced = r.synced > 0;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      cart.clear();
      roundOff = 0;
    });
    await _reload();
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(synced ? 'Sale synchronized' : 'Offline invoice saved'),
        content: Text(
          '$localNo\n${synced ? 'Server sync completed.' : 'The invoice is safe on this device and will retry automatically.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'none'),
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'share'),
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'print'),
            child: const Text('Print'),
          ),
        ],
      ),
    );
    if (action == 'print')
      await receipt.printReceipt(
        session: widget.session,
        localNumber: localNo,
        payload: payload,
        synced: synced,
        requestId: request,
      );
    if (action == 'share')
      await receipt.shareReceipt(
        session: widget.session,
        localNumber: localNo,
        payload: payload,
        synced: synced,
        requestId: request,
      );
  }

  Future<void> sendKot() async {
    if (!widget.session.restaurantEnabled || cart.isEmpty) return;
    final note = TextEditingController();
    String orderType = 'takeaway';
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('KOT groundwork'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: orderType,
                items: const [
                  DropdownMenuItem(value: 'takeaway', child: Text('Takeaway')),
                  DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                ],
                onChanged: (v) => setLocal(() => orderType = v ?? 'takeaway'),
                decoration: const InputDecoration(labelText: 'Order type'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Kitchen note'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Send KOT'),
            ),
          ],
        ),
      ),
    );
    if (go != true) {
      note.dispose();
      return;
    }
    try {
      final items = cart
          .map(
            (x) => {
              'variant_id': x.product.variantId,
              'quantity': x.quantity,
              'unit_id': x.unit.unitId.isEmpty ? null : x.unit.unitId,
              'unit_price': x.unitPrice,
              'discount_amount': 0,
              'tax_rate': x.product.taxRate,
              'item_note': '',
            },
          )
          .toList();
      final r = await kot.create(
        session: widget.session,
        requestId: const Uuid().v4(),
        orderType: orderType,
        customerId: customer?.id,
        items: items,
        note: note.text,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'KOT sent: ${r['kot_number'] ?? r['order_number'] ?? 'OK'}',
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KOT requires online restaurant access: $e')),
        );
    } finally {
      note.dispose();
    }
  }

  Future<void> menu(String value) async {
    if (value == 'queue') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfflineQueueScreen(session: widget.session),
        ),
      );
      _heartbeat();
    } else if (value == 'refresh') {
      setState(() => loading = true);
      try {
        await sync.refreshCatalogue(widget.session);
        await _reload();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline cache refreshed.')),
          );
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      } finally {
        if (mounted) setState(() => loading = false);
      }
    } else if (value == 'signout') {
      await MobilePosAuthService().signOut();
      if (mounted)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MobilePosEntryScreen()),
          (_) => false,
        );
    } else if (value == 'deactivate') {
      await MobilePosAuthService().signOut();
      await DeviceInstallationService().clearActivation();
      if (mounted)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MobilePosEntryScreen()),
          (_) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = filtered;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mobile POS'),
            Text(
              '${widget.session.locationCode} | ${widget.session.deviceCode}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scan barcode / serial',
            onPressed: scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'queue', child: Text('Offline Sync')),
              PopupMenuItem(value: 'refresh', child: Text('Refresh cache')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
              PopupMenuItem(
                value: 'deactivate',
                child: Text('Deactivate phone'),
              ),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          syncText.startsWith('Offline')
                              ? Icons.cloud_off
                              : Icons.cloud_done,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(syncText)),
                        TextButton.icon(
                          onPressed: chooseCustomer,
                          icon: const Icon(Icons.person_outline),
                          label: Text(customer?.name ?? 'Customer'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search products / SKU / barcode',
                      suffixIcon: IconButton(
                        tooltip: 'Scan barcode / serial',
                        onPressed: scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 190,
                                mainAxisExtent: 140,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final p = rows[i];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _addProduct(p),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        p.sku,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      const Spacer(),
                                      Text(
                                        money(
                                          p.defaultUnit.salePrice > 0
                                              ? p.defaultUnit.salePrice
                                              : p.sellingPrice,
                                        ),
                                      ),
                                      Text(
                                        p.itemType == 'stock'
                                            ? 'Avail ${p.stockQuantity.toStringAsFixed(2)} ${p.baseUnitCode}'
                                            : p.itemType,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width > 700)
                        SizedBox(width: 360, child: _cartPanel()),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width <= 700)
                  SizedBox(height: 250, child: _cartPanel()),
              ],
            ),
    );
  }

  Widget _cartPanel() => Card(
    margin: const EdgeInsets.all(8),
    child: Column(
      children: [
        ListTile(
          title: Text('Cart (${cart.length})'),
          subtitle: Text(customer?.name ?? 'Select customer'),
          trailing: widget.session.restaurantEnabled
              ? IconButton(
                  onPressed: cart.isEmpty ? null : sendKot,
                  tooltip: 'Send KOT',
                  icon: const Icon(Icons.soup_kitchen_outlined),
                )
              : null,
        ),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Scan or tap a product'))
              : ListView.builder(
                  itemCount: cart.length,
                  itemBuilder: (_, i) {
                    final l = cart[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        l.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l.serialNumbers.isNotEmpty
                            ? 'Serial ${l.serialNumbers.join(', ')}'
                            : '${l.quantity.toStringAsFixed(l.quantity % 1 == 0 ? 0 : 2)} ${l.unit.code} Ã— ${money(l.unitPrice)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (l.product.trackingMode != 'serial' &&
                              l.product.saleUnits.length > 1)
                            TextButton(
                              onPressed: () => _chooseUnit(l),
                              child: Text(l.unit.code),
                            ),
                          if (l.product.trackingMode != 'serial')
                            IconButton(
                              onPressed: () => _qty(l, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          Text(money(l.total)),
                          IconButton(
                            onPressed: () => setState(() => cart.remove(l)),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  roundOff.abs() > 0.000001
                      ? 'Total ${money(total)}\nRound ${money(roundOff)}'
                      : 'Total\n${money(total)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: cart.isEmpty ? null : applyRoundOff,
                icon: const Icon(Icons.exposure_zero),
                label: const Text('Round'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: cart.isEmpty ? null : checkout,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('PAY'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PaymentResult {
  final String method, reference;
  final double paid;
  const _PaymentResult(this.method, this.reference, this.paid);
}

class _PaymentDialog extends StatefulWidget {
  final double total;
  final String currency;
  final bool allowCredit;
  const _PaymentDialog({
    required this.total,
    required this.currency,
    required this.allowCredit,
  });
  @override
  State<_PaymentDialog> createState() => _PaymentState();
}

class _PaymentState extends State<_PaymentDialog> {
  String method = 'cash';
  late final TextEditingController amount, reference;
  @override
  void initState() {
    super.initState();
    amount = TextEditingController(text: widget.total.toStringAsFixed(2));
    reference = TextEditingController();
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      'Payment â€¢ ${widget.currency} ${widget.total.toStringAsFixed(2)}',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: method,
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Cash')),
            DropdownMenuItem(value: 'card', child: Text('Card')),
            DropdownMenuItem(value: 'upi', child: Text('UPI')),
            DropdownMenuItem(value: 'bank', child: Text('Bank')),
          ],
          onChanged: (v) => setState(() => method = v ?? 'cash'),
          decoration: const InputDecoration(labelText: 'Method'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: widget.allowCredit
                ? 'Amount paid (partial allowed)'
                : 'Amount paid',
            prefixText: '${widget.currency} ',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: reference,
          decoration: const InputDecoration(labelText: 'Reference (optional)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final paid = double.tryParse(amount.text) ?? 0;
          if (paid < 0 || paid > widget.total + 0.01) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid payment amount.')),
            );
            return;
          }
          if (!widget.allowCredit && (paid - widget.total).abs() > 0.01) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Walk-in customer must be fully paid.'),
              ),
            );
            return;
          }
          Navigator.pop(
            context,
            _PaymentResult(method, reference.text.trim(), paid),
          );
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}
