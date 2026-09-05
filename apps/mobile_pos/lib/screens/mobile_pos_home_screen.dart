// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
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
      if (mounted) setState(() => syncText = 'Offline â€¢ invoices stay queued');
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
        ThqNotify.showSnackBar(
          context,
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
      ThqNotify.showSnackBar(
        context,
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
          ThqNotify.showSnackBar(
            context,
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
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('No offline stock available.')),
      );
      return;
    }
    if (serial != null && cart.any((l) => l.serialNumbers.contains(serial))) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Serial already added.')),
      );
      return;
    }
    if (serial == null && p.trackingMode != 'serial') {
      for (final l in cart) {
        if (l.product.variantId == p.variantId && l.unit.code == unit.code) {
          final next = l.quantity + step;
          if (p.itemType == 'stock' &&
              next * l.unit.conversionToBase > p.stockQuantity + 0.000001) {
            ThqNotify.showSnackBar(
              context,
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
      ThqNotify.showSnackBar(
        context,
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
      ThqNotify.showSnackBar(
        context,
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
    final creditAmount = (total - result.paid).clamp(0, double.infinity);
    final paymentAllocations = <Map<String, dynamic>>[];
    if (result.paid > 0.005) {
      paymentAllocations.add({
        'method_code': result.method,
        'tendered_amount': result.paid,
        'reference_number': result.reference,
      });
    }
    if (creditAmount > 0.005) {
      paymentAllocations.add({
        'method_code': 'credit',
        'tendered_amount': creditAmount,
        'reference_number': null,
      });
    }
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
      'payment_allocations': paymentAllocations,
      'notes': 'Mobile POS',
      'total': total,
      'outstanding': creditAmount,
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
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Could not save local invoice: $e')),
        );
      return;
    }
    var synced = false;
    Map<String, dynamic>? serverResponse;
    try {
      final r = await sync.sync(widget.session, only: request);
      synced = r.synced > 0;
      if (synced) {
        final saved = await local.invoiceByRequest(request);
        serverResponse = saved?.serverResponse;
        if (serverResponse == null ||
            serverResponse['sale_id'] == null ||
            serverResponse['gst_snapshot_id'] == null ||
            serverResponse['gst_journal_id'] == null) {
          throw StateError(
            'Synced sale is missing authoritative receipt evidence.',
          );
        }
      }
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
        serverResponse: serverResponse,
        requestId: request,
      );
    if (action == 'share')
      await receipt.shareReceipt(
        session: widget.session,
        localNumber: localNo,
        payload: payload,
        synced: synced,
        serverResponse: serverResponse,
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
        ThqNotify.showSnackBar(
          context,
          SnackBar(
            content: Text(
              'KOT sent: ${r['kot_number'] ?? r['order_number'] ?? 'OK'}',
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ThqNotify.showSnackBar(
          context,
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
          ThqNotify.showSnackBar(
            context,
            const SnackBar(content: Text('Offline cache refreshed.')),
          );
      } catch (e) {
        if (mounted)
          ThqNotify.showSnackBar(
            context,
            SnackBar(content: Text('Refresh failed: $e')),
          );
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
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final compact = size.width <= 700;
    final mobileCartHeight = (size.height * 0.34)
        .clamp(220.0, 300.0)
        .toDouble();
    final normalizedSync = syncText.toLowerCase();
    final offline = normalizedSync.startsWith('offline');
    final conflict = normalizedSync.contains('conflict');
    final syncIcon = conflict
        ? Icons.warning_amber_rounded
        : offline
        ? Icons.cloud_off_rounded
        : Icons.cloud_done_rounded;
    final syncColor = conflict || offline
        ? const Color(0xFFFFC857)
        : const Color(0xFF8AE3B0);

    return Scaffold(
      body: loading
          ? const SafeArea(child: ThqLoadingState(label: 'Preparing POS...'))
          : Column(
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(14, topInset + 10, 8, 11),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5142C7), Color(0xFF7C6EF0)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Text(
                              'T',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'THQ POS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.25,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.session.locationCode} | ${widget.session.deviceCode}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Scan barcode / serial',
                            onPressed: scan,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.13,
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'POS menu',
                            onSelected: menu,
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
                            ),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'queue',
                                child: Text('Offline Sync'),
                              ),
                              PopupMenuItem(
                                value: 'refresh',
                                child: Text('Refresh cache'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'signout',
                                child: Text('Sign out'),
                              ),
                              PopupMenuItem(
                                value: 'deactivate',
                                child: Text('Deactivate phone'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxWidth: 210),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(syncIcon, size: 15, color: syncColor),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    syncText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: chooseCustomer,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                            ),
                            icon: const Icon(Icons.person_outline_rounded),
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? 115 : 180,
                              ),
                              child: Text(
                                customer?.name ?? 'Customer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search product, SKU or barcode',
                      suffixIcon: IconButton(
                        tooltip: 'Scan barcode / serial',
                        onPressed: scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: rows.isEmpty
                            ? const ThqEmptyState(
                                title: 'No products found',
                                message:
                                    'Try a different search or refresh the offline catalogue.',
                                icon: Icons.inventory_2_outlined,
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  3,
                                  10,
                                  9,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: compact ? 175 : 190,
                                      mainAxisExtent: compact ? 126 : 136,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: rows.length,
                                itemBuilder: (_, i) {
                                  final p = rows[i];
                                  final unitPrice = p.defaultUnit.salePrice > 0
                                      ? p.defaultUnit.salePrice
                                      : p.sellingPrice;
                                  final stockLabel = p.itemType == 'stock'
                                      ? 'Avail ${p.stockQuantity.toStringAsFixed(2)} ${p.baseUnitCode}'
                                      : p.itemType;

                                  return Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(15),
                                    child: InkWell(
                                      onTap: () => _addProduct(p),
                                      borderRadius: BorderRadius.circular(15),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE5E6EE),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 29,
                                                  height: 29,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF0EDFF,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          9,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.inventory_2_outlined,
                                                    size: 16,
                                                    color: Color(0xFF6252D9),
                                                  ),
                                                ),
                                                const Spacer(),
                                                if (p.trackingMode == 'serial')
                                                  const Icon(
                                                    Icons.qr_code_2_rounded,
                                                    size: 16,
                                                    color: Color(0xFF777985),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 7),
                                            Text(
                                              p.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1.15,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              money(unitPrice),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              stockLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF747681),
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (!compact)
                        SizedBox(width: 370, child: _cartPanel(compact: false)),
                    ],
                  ),
                ),
                if (compact)
                  SizedBox(
                    height: mobileCartHeight,
                    child: _cartPanel(compact: true),
                  ),
              ],
            ),
    );
  }

  Widget _cartPanel({required bool compact}) => Container(
    margin: compact
        ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
        : const EdgeInsets.fromLTRB(0, 3, 8, 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFE3E4EC)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.055),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EDFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: Color(0xFF6252D9),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cart | ${cart.length} item${cart.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        customer?.name ?? 'Select customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF747681),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.session.restaurantEnabled)
                  IconButton(
                    onPressed: cart.isEmpty ? null : sendKot,
                    tooltip: 'Send KOT',
                    icon: const Icon(Icons.soup_kitchen_outlined),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Scan or tap a product to start billing.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF777985),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (_, i) {
                      final l = cart[i];
                      final quantityText = l.quantity.toStringAsFixed(
                        l.quantity % 1 == 0 ? 0 : 2,
                      );

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.product.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l.serialNumbers.isNotEmpty
                                            ? 'Serial ${l.serialNumbers.join(', ')}'
                                            : '$quantityText ${l.unit.code} x ${money(l.unitPrice)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF777985),
                                          fontSize: 9.8,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  money(l.total),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (l.product.trackingMode != 'serial' &&
                                    l.product.saleUnits.length > 1)
                                  TextButton(
                                    onPressed: () => _chooseUnit(l),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 30),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: Text(l.unit.code),
                                  ),
                                const Spacer(),
                                if (l.product.trackingMode != 'serial')
                                  IconButton(
                                    tooltip: 'Reduce quantity',
                                    onPressed: () => _qty(l, -1),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size.square(30),
                                      padding: const EdgeInsets.all(5),
                                    ),
                                    icon: const Icon(
                                      Icons.remove_rounded,
                                      size: 17,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Remove item',
                                  onPressed: () =>
                                      setState(() => cart.remove(l)),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size.square(30),
                                    padding: const EdgeInsets.all(5),
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(11, 8, 9, 9),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              border: Border(top: BorderSide(color: Color(0xFFE7E8EF))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Color(0xFF777985),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        money(total),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (roundOff.abs() > 0.000001)
                        Text(
                          'Round ${money(roundOff)}',
                          style: const TextStyle(
                            color: Color(0xFF777985),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Apply round off',
                  onPressed: cart.isEmpty ? null : applyRoundOff,
                  icon: const Icon(Icons.exposure_zero_rounded),
                ),
                const SizedBox(width: 5),
                FilledButton.icon(
                  onPressed: cart.isEmpty ? null : checkout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(108, 46),
                    backgroundColor: const Color(0xFF6252D9),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('PAY'),
                ),
              ],
            ),
          ),
        ],
      ),
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
            ThqNotify.showSnackBar(
              context,
              const SnackBar(content: Text('Invalid payment amount.')),
            );
            return;
          }
          if (!widget.allowCredit && (paid - widget.total).abs() > 0.01) {
            ThqNotify.showSnackBar(
              context,
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
