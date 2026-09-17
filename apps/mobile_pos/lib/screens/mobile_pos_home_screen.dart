// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:thq_logistics/thq_logistics.dart';
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
import 'mobile_pos_payment_screen.dart';
import 'mobile_pos_report_screen.dart';
import 'mobile_pos_purchase_screen.dart';
import 'mobile_pos_expense_screen.dart';
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
  String _productSection = 'All';
  String _category = 'All';
  String _sort = 'name';
  bool _manualOffline = false;
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
    final stored = await local.getMeta(
      'manual_offline:${widget.session.tenantId}:${widget.session.deviceId}',
    );
    _manualOffline = stored == true;

    if (_manualOffline) {
      syncText = 'Offline | manual mode';
    } else {
      try {
        await sync.refreshCatalogue(widget.session);
        syncText = 'Online | cache refreshed';
      } catch (_) {
        syncText = 'Offline | using local cache';
      }
    }

    await _reload();
    if (mounted) setState(() => loading = false);
    if (!_manualOffline) unawaited(_heartbeat());
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
    if (syncing || _manualOffline) return;
    syncing = true;
    try {
      final r = await sync.sync(widget.session);
      if (r.synced > 0) {
        await _reload();
      }
      final summary = await local.summary(
        widget.session.tenantId,
        widget.session.deviceId,
      );
      final conflicts = summary['conflict'] ?? 0;
      final waiting = (summary['pending'] ?? 0) +
          (summary['error'] ?? 0) +
          (summary['syncing'] ?? 0);
      if (mounted) {
        setState(
          () => syncText = conflicts > 0
              ? '$conflicts conflict(s) need attention'
              : waiting > 0
                  ? 'Online | $waiting invoice(s) waiting to sync'
                  : 'Synced',
        );
      }
    } catch (_) {
      if (mounted) setState(() => syncText = 'Offline | invoices stay queued');
    } finally {
      syncing = false;
    }
  }

  List<String> get _categoryOptions {
    final values = products
        .map((product) => product.categoryName.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['All', ...values];
  }

  bool _matchesProductFilter(MobileProduct product) {
    switch (_productSection) {
      case 'Stock':
        return product.itemType == 'stock';
      case 'Serial':
        return product.trackingMode == 'serial';
      case 'Batch':
        return product.trackingMode == 'batch';
      case 'Service':
        return product.itemType != 'stock';
      default:
        return true;
    }
  }
  List<MobileProduct> get filtered {
    final q = search.text.trim().toLowerCase();
    final rows = products.where((product) {
      if (_category != 'All' && product.categoryName != _category) {
        return false;
      }
      if (!_matchesProductFilter(product)) return false;
      if (q.isEmpty) return true;
      return product.name.toLowerCase().contains(q) ||
          product.sku.toLowerCase().contains(q) ||
          product.barcode.toLowerCase().contains(q) ||
          product.searchCodes.toLowerCase().contains(q) ||
          product.categoryName.toLowerCase().contains(q) ||
          product.brandName.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case 'name_desc':
        rows.sort((a, b) => b.name.compareTo(a.name));
        break;
      case 'price_low':
        rows.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
        break;
      case 'price_high':
        rows.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
        break;
      case 'stock_high':
        rows.sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
        break;
      case 'stock_low':
        rows.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
        break;
      default:
        rows.sort((a, b) => a.name.compareTo(b.name));
    }

    return rows.take(200).toList();
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
    if (_manualOffline) {
      line.resolvedUnitPrice = null;
      line.pricingSource = 'cached';
      return;
    }
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

    final payment = await Navigator.of(context).push<MobilePaymentResult>(
      MaterialPageRoute(
        builder: (_) => MobilePosPaymentScreen(
          currencyCode: widget.session.currencyCode,
          customerName: customer!.name,
          allowCredit: customer?.isWalkIn != true,
          initialRoundOff: roundOff,
          lines: cart
              .map(
                (line) => MobilePaymentLine(
                  name: line.product.name,
                  sku: line.product.sku,
                  quantity: line.quantity,
                  unitCode: line.unit.code,
                  unitPrice: line.unitPrice,
                  taxRate: line.product.taxRate,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    if (payment == null || !mounted) return;

    final request = const Uuid().v4();
    final now = DateTime.now();
    final subtotal = cart.fold<double>(
      0,
      (sum, line) => sum + (line.quantity * line.unitPrice),
    );

    final items = cart.map((line) {
      final payload = line.toPayload();
      final gross = line.quantity * line.unitPrice;
      final allocatedDiscount = subtotal <= 0
          ? 0.0
          : payment.discountAmount * (gross / subtotal);
      payload['discount_amount'] = allocatedDiscount
          .clamp(0, gross)
          .toDouble();
      return payload;
    }).toList(growable: false);

    final paymentAllocations = payment.allocations
        .map((allocation) => allocation.toMap())
        .toList(growable: false);
    final creditAmount = payment.allocations
        .where((allocation) => allocation.methodCode == 'credit')
        .fold<double>(0, (sum, allocation) => sum + allocation.amount);
    final noteParts = <String>['Mobile POS'];
    if (payment.notes.trim().isNotEmpty) noteParts.add(payment.notes.trim());

    final payload = <String, dynamic>{
      'customer_id': customer!.id,
      'customer_name': customer!.name,
      'sale_date': DateFormat('yyyy-MM-dd').format(now),
      'sale_time': now.toIso8601String(),
      'due_date': creditAmount > 0.005
          ? DateFormat('yyyy-MM-dd').format(
              now.add(const Duration(days: 30)),
            )
          : null,
      'items': items,
      'additional_charges': 0,
      'round_off': payment.roundOff,
      'initial_payment': payment.paidAmount,
      'payment_method': payment.primaryMethod,
      'payment_reference': payment.primaryReference,
      'payment_allocations': paymentAllocations,
      'notes': noteParts.join(' • '),
      'discount_amount': payment.discountAmount,
      'cash_received': payment.cashReceived,
      'total': payment.total,
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
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Could not save local invoice: $e')),
        );
      }
      return;
    }

    var synced = false;
    Map<String, dynamic>? serverResponse;
    if (!_manualOffline) {
      try {
        final result = await sync.sync(widget.session, only: request);
        synced = result.synced > 0;
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
      } catch (_) {
        // The durable local invoice stays queued until the next successful sync.
      }
    }

    if (!mounted) return;
    setState(() {
      cart.clear();
      roundOff = 0;
    });
    await _reload();
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(synced ? 'Sale synchronized' : 'Offline invoice saved'),
        content: Text(
          '$localNo\n${synced ? 'Server sync completed.' : 'The invoice is safe on this device and will sync when you press Sync or return online.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'none'),
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'share'),
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'print'),
            child: const Text('Print'),
          ),
        ],
      ),
    );

    if (action == 'print') {
      await receipt.printReceipt(
        session: widget.session,
        localNumber: localNo,
        payload: payload,
        synced: synced,
        serverResponse: serverResponse,
        requestId: request,
      );
    }
    if (action == 'share') {
      await receipt.shareReceipt(
        session: widget.session,
        localNumber: localNo,
        payload: payload,
        synced: synced,
        serverResponse: serverResponse,
        requestId: request,
      );
    }
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

  Future<void> _syncNow() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      final result = await sync.sync(
        widget.session,
        includeConflicts: true,
      );
      var catalogueRefreshed = false;
      try {
        await sync.refreshCatalogue(widget.session);
        catalogueRefreshed = true;
      } catch (_) {}
      await _reload();
      final summary = await local.summary(
        widget.session.tenantId,
        widget.session.deviceId,
      );
      final conflicts = summary['conflict'] ?? 0;
      final waiting = (summary['pending'] ?? 0) +
          (summary['error'] ?? 0) +
          (summary['syncing'] ?? 0);
      if (!mounted) return;
      setState(() {
        if (_manualOffline) {
          syncText = conflicts > 0
              ? 'Offline | $conflicts conflict(s)'
              : 'Offline | manual mode';
        } else if (conflicts > 0) {
          syncText = '$conflicts conflict(s) need attention';
        } else if (waiting > 0 && !catalogueRefreshed) {
          syncText = 'Offline | $waiting invoice(s) queued';
        } else if (waiting > 0) {
          syncText = 'Online | $waiting invoice(s) waiting to sync';
        } else {
          syncText = 'Synced';
        }
      });
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(
            content: Text(
              'Sync: ${result.synced} synced, $waiting waiting, '
              '$conflicts conflict(s).',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => syncText = _manualOffline
              ? 'Offline | manual mode'
              : 'Offline | invoices stay queued',
        );
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Sync unavailable: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> _setManualOffline(bool enabled) async {
    if (enabled) {
      final cached = await local.products(
        widget.session.tenantId,
        widget.session.locationId,
      );
      if (cached.isEmpty) {
        if (mounted) {
          ThqNotify.showSnackBar(
            context,
            const SnackBar(
              content: Text(
                'Offline mode needs a cached catalogue. Connect and sync once first.',
              ),
            ),
          );
        }
        return;
      }
    }

    await local.setMeta(
      'manual_offline:${widget.session.tenantId}:${widget.session.deviceId}',
      enabled,
    );
    if (!mounted) return;
    setState(() {
      _manualOffline = enabled;
      syncText = enabled ? 'Offline | manual mode' : 'Going online...';
    });

    if (!enabled) {
      await _syncNow();
    }
  }

  Future<void> menu(String value) async {
    if (value == 'work_offline') {
      await _setManualOffline(true);
    } else if (value == 'go_online') {
      await _setManualOffline(false);
    } else if (value == 'queue') {
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
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final wideLandscape = size.width > size.height;
    final showSidebar = size.width >= 1180 && wideLandscape;
    final showCartPanel = size.width >= 1080 && wideLandscape;
    final filteredRows = filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      drawer: showSidebar ? null : Drawer(child: _sideMenu(inDrawer: true)),
      body: SafeArea(
        child: loading
            ? const ThqLoadingState(label: 'Preparing POS...')
            : Row(
                children: [
                  if (showSidebar)
                    SizedBox(width: 205, child: _sideMenu(inDrawer: false)),
                  Expanded(
                    child: Column(
                      children: [
                        _topBar(compact: compact, hasPermanentSidebar: showSidebar),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 8 : 12,
                              8,
                              compact ? 8 : 12,
                              compact ? 8 : 12,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFDDE5EE),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.035),
                                    blurRadius: 18,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  _summaryStrip(compact: compact),
                                  const Divider(height: 1),
                                  _catalogueToolbar(compact: compact),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: filteredRows.isEmpty
                                              ? const ThqEmptyState(
                                                  title: 'No products found',
                                                  message:
                                                      'Try another search/filter or refresh the offline catalogue.',
                                                  icon: Icons.inventory_2_outlined,
                                                )
                                              : _productGrid(
                                                  filteredRows,
                                                  compact: compact,
                                                ),
                                        ),
                                        if (showCartPanel) ...[
                                          const VerticalDivider(width: 1),
                                          SizedBox(
                                            width: size.width >= 1280 ? 365 : 345,
                                            child: _cartPanel(compact: false),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!showCartPanel) ...[
                                    const Divider(height: 1),
                                    _mobileCartBar(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _topBar({
    required bool compact,
    required bool hasPermanentSidebar,
  }) {
    final normalizedSync = syncText.toLowerCase();
    final offline = _manualOffline || normalizedSync.startsWith('offline');
    final conflict = normalizedSync.contains('conflict');
    final statusColor = conflict
        ? const Color(0xFFD78B00)
        : offline
            ? const Color(0xFFD06458)
            : const Color(0xFF159A5C);
    final statusIcon = conflict
        ? Icons.warning_amber_rounded
        : offline
            ? Icons.cloud_off_rounded
            : Icons.cloud_done_rounded;
    final statusLabel = _manualOffline ? 'Offline | manual' : syncText;

    return Container(
      height: compact ? 64 : 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE6EBF2)),
        ),
      ),
      child: Row(
        children: [
          if (!hasPermanentSidebar)
            Builder(
              builder: (menuContext) => IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(menuContext).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          if (!hasPermanentSidebar) const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sales',
                  style: TextStyle(
                    color: Color(0xFF14233B),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                if (!compact)
                  const Text(
                    'Scan products, build the order and complete the sale',
                    style: TextStyle(
                      color: Color(0xFF768398),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (!compact)
            Tooltip(
              message: _manualOffline
                  ? 'Manual offline mode is enabled'
                  : 'Connection / queue status',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _setManualOffline(!_manualOffline),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.16)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 15, color: statusColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!compact) const SizedBox(width: 6),
          IconButton(
            tooltip: 'Sync now',
            onPressed: syncing ? null : _syncNow,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF8F0),
              foregroundColor: const Color(0xFF159A5C),
            ),
            icon: syncing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Scan barcode / serial',
            onPressed: scan,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF3FF),
              foregroundColor: const Color(0xFF147AF3),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'POS menu',
            onSelected: menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _manualOffline ? 'go_online' : 'work_offline',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _manualOffline
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(
                    _manualOffline ? 'Go online' : 'Work offline',
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'queue',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync_alt_rounded),
                  title: Text('Synced / Not Synced'),
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Refresh catalogue'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
              const PopupMenuItem(
                value: 'deactivate',
                child: Text('Deactivate phone'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sideMenu({required bool inDrawer}) {
    const side = Color(0xFF102238);
    const muted = Color(0xFFB8C6D8);
    return Material(
      color: side,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF147AF3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'T',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'THQ ERP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Mobile POS',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _navItem(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Sales',
                        active: true,
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                        },
                      ),
                      _navItem(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Purchase',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => MobilePosPurchaseScreen(
                                    session: widget.session,
                                    offlineMode: _manualOffline,
                                  ),
                                ),
                              )
                              .then((changed) {
                                if (changed == true) _reload();
                              });
                        },
                      ),
                      _navItem(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Expense',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => MobilePosExpenseScreen(
                                session: widget.session,
                                offlineMode: _manualOffline,
                              ),
                            ),
                          );
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Divider(color: Color(0xFF27405A), height: 1),
                      ),
                      _navItem(
                        icon: Icons.inventory_2_outlined,
                        label: 'Products',
                        onTap: () => _moduleQueued('Products', inDrawer),
                      ),
                      _navItem(
                        icon: Icons.people_outline_rounded,
                        label: 'Customers',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          chooseCustomer();
                        },
                      ),
                      _navItem(
                        icon: Icons.route_outlined,
                        label: 'Logistics Operations',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LogisticsOperationsWorkspace(
                                tenantId: widget.session.tenantId,
                                locationId: widget.session.locationId,
                              ),
                            ),
                          );
                        },
                      ),
                      _navItem(
                        icon: Icons.local_shipping_outlined,
                        label: 'Vehicle Logistics',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VehicleLogisticsReportWorkspace(
                                tenantId: widget.session.tenantId,
                                locationId: widget.session.locationId,
                              ),
                            ),
                          );
                        },
                      ),
                      _navItem(
                        icon: Icons.bar_chart_rounded,
                        label: 'Reports',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MobilePosReportScreen(
                                session: widget.session,
                              ),
                            ),
                          );
                        },
                      ),
                      _navItem(
                        icon: Icons.sync_alt_rounded,
                        label: 'Offline & Sync',
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OfflineQueueScreen(session: widget.session),
                                ),
                              )
                              .then((_) => _heartbeat());
                        },
                      ),
                      _navItem(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () => _moduleQueued('Settings', inDrawer),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.locationCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.session.deviceCode}  •  v${ThqReleaseContract.appVersion} B${ThqReleaseContract.buildNumber}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: active ? const Color(0xFF147AF3) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    icon,
                    size: 20,
                    color: active
                        ? Colors.white
                        : const Color(0xFFB8C6D8),
                  ),
                  const SizedBox(width: 11),
                  Text(
                    label,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : const Color(0xFFD5DFEA),
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _moduleQueued(String name, bool inDrawer) {
    if (inDrawer) Navigator.of(context).pop();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('$name workspace is included in the next Mobile POS build step.'),
        ),
      );
    });
  }

  Widget _summaryStrip({required bool compact}) {
    final quantity = cart.fold<double>(0, (sum, line) => sum + line.quantity);
    final cards = <Widget>[
      _metricCard(
        icon: Icons.inventory_2_outlined,
        label: 'Products',
        value: '${products.length}',
        accent: const Color(0xFF147AF3),
      ),
      _metricCard(
        icon: Icons.shopping_cart_outlined,
        label: 'Cart items',
        value: quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
        accent: const Color(0xFF14A765),
      ),
      _metricCard(
        icon: Icons.person_outline_rounded,
        label: 'Customer',
        value: customer?.name ?? 'Select',
        accent: const Color(0xFF7C56D9),
        onTap: chooseCustomer,
      ),
      _metricCard(
        icon: Icons.cloud_done_outlined,
        label: 'Status',
        value: syncText,
        accent: const Color(0xFFD18A00),
        onTap: _syncNow,
      ),
    ];

    if (compact) {
      return SizedBox(
        height: 62,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => SizedBox(width: 138, child: cards[index]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      child: Row(
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            Expanded(child: cards[index]),
            if (index < cards.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    VoidCallback? onTap,
  }) =>
      Material(
        color: const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7EDF4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7A8798),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF14233B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _catalogueToolbar({required bool compact}) {
    InputDecoration dropdownDecoration(String label, IconData icon) =>
        InputDecoration(
          isDense: true,
          labelText: label,
          prefixIcon: Icon(icon, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search product, SKU or barcode',
                    suffixIcon: IconButton(
                      tooltip: 'Scan barcode / serial',
                      onPressed: scan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: chooseCustomer,
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      customer?.name ?? 'Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('category-$_category'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: dropdownDecoration(
                    'Category',
                    Icons.category_outlined,
                  ),
                  items: _categoryOptions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('filter-$_productSection'),
                  initialValue: _productSection,
                  isExpanded: true,
                  decoration: dropdownDecoration(
                    'Filter',
                    Icons.filter_alt_outlined,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All products')),
                    DropdownMenuItem(value: 'Stock', child: Text('Stock')),
                    DropdownMenuItem(value: 'Serial', child: Text('Serial')),
                    DropdownMenuItem(value: 'Batch', child: Text('Batch')),
                    DropdownMenuItem(value: 'Service', child: Text('Service')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _productSection = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('sort-$_sort'),
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: dropdownDecoration(
                    'Sort',
                    Icons.swap_vert_rounded,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name A-Z')),
                    DropdownMenuItem(
                      value: 'name_desc',
                      child: Text('Name Z-A'),
                    ),
                    DropdownMenuItem(
                      value: 'price_low',
                      child: Text('Price low-high'),
                    ),
                    DropdownMenuItem(
                      value: 'price_high',
                      child: Text('Price high-low'),
                    ),
                    DropdownMenuItem(
                      value: 'stock_high',
                      child: Text('Stock high-low'),
                    ),
                    DropdownMenuItem(
                      value: 'stock_low',
                      child: Text('Stock low-high'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productGrid(List<MobileProduct> rows, {required bool compact}) =>
      GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: compact ? 205 : 195,
          mainAxisExtent: compact ? 136 : 144,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: rows.length,
        itemBuilder: (_, index) => _productCard(rows[index]),
      );

  Widget _productCard(MobileProduct product) {
    final unitPrice = product.defaultUnit.salePrice > 0
        ? product.defaultUnit.salePrice
        : product.sellingPrice;
    final available = product.itemType == 'stock'
        ? '${product.stockQuantity.toStringAsFixed(product.stockQuantity % 1 == 0 ? 0 : 2)} ${product.baseUnitCode}'
        : product.itemType;
    final lowStock = product.itemType == 'stock' && product.stockQuantity <= 3;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _addProduct(product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDF1F5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      product.trackingMode == 'serial'
                          ? Icons.qr_code_2_rounded
                          : product.itemType == 'stock'
                              ? Icons.inventory_2_outlined
                              : Icons.miscellaneous_services_outlined,
                      color: const Color(0xFF147AF3),
                      size: 17,
                    ),
                  ),
                  const Spacer(),
                  if (product.trackingMode == 'serial' ||
                      product.trackingMode == 'batch')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1ECFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        product.trackingMode.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF7148CB),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF14233B),
                  fontSize: 12,
                  height: 1.10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                money(unitPrice),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF14233B),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: lowStock
                      ? const Color(0xFFFFF3E5)
                      : const Color(0xFFEAF8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  product.itemType == 'stock' ? 'Stock $available' : available,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: lowStock
                        ? const Color(0xFFB06B00)
                        : const Color(0xFF148553),
                    fontSize: 8.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartPanel({required bool compact, VoidCallback? refreshOverlay}) => Container(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: Color(0xFF147AF3),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Order • ${cart.length}',
                          style: const TextStyle(
                            color: Color(0xFF14233B),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          customer?.name ?? 'Select customer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF758296),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Customer',
                    onPressed: () async {
                      await chooseCustomer();
                      refreshOverlay?.call();
                    },
                    icon: const Icon(Icons.person_outline_rounded, size: 19),
                  ),
                  if (cart.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear cart',
                      onPressed: () {
                        setState(() {
                          cart.clear();
                          roundOff = 0;
                        });
                        refreshOverlay?.call();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: cart.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 34,
                              color: Color(0xFFB3BECC),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Your order is empty',
                              style: TextStyle(
                                color: Color(0xFF526174),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Scan or tap a product to start billing.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8793A3),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: cart.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                      ),
                      itemBuilder: (_, index) => _cartLine(
                        cart[index],
                        refreshOverlay: refreshOverlay,
                      ),
                    ),
            ),
            if (widget.session.restaurantEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: cart.isEmpty ? null : sendKot,
                    icon: const Icon(Icons.soup_kitchen_outlined),
                    label: const Text('Send KOT'),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFCFE),
                border: Border(top: BorderSide(color: Color(0xFFE7EDF4))),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Subtotal + tax',
                        style: TextStyle(
                          color: Color(0xFF768398),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        money(beforeRoundOff),
                        style: const TextStyle(
                          color: Color(0xFF14233B),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (roundOff.abs() > 0.000001) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          'Round off',
                          style: TextStyle(
                            color: Color(0xFF768398),
                            fontSize: 10.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          money(roundOff),
                          style: const TextStyle(
                            color: Color(0xFF768398),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total',
                          style: TextStyle(
                            color: Color(0xFF14233B),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        money(total),
                        style: const TextStyle(
                          color: Color(0xFF147AF3),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () {
                                  applyRoundOff();
                                  refreshOverlay?.call();
                                },
                          icon: const Icon(Icons.exposure_zero_rounded),
                          label: const Text('Round'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : compact
                                  ? _payFromCartPage
                                  : checkout,
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Pay now'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: const Color(0xFF14A765),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _cartLine(CartLine line, {VoidCallback? refreshOverlay}) {
    final quantityText = line.quantity.toStringAsFixed(
      line.quantity % 1 == 0 ? 0 : 2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 8, 7, 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Color(0xFF53677D),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF14233B),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.serialNumbers.isNotEmpty
                          ? 'Serial ${line.serialNumbers.join(', ')}'
                          : '$quantityText ${line.unit.code} × ${money(line.unitPrice)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7A8798),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                money(line.total),
                style: const TextStyle(
                  color: Color(0xFF14233B),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              if (line.product.trackingMode != 'serial' &&
                  line.product.saleUnits.length > 1)
                TextButton(
                  onPressed: () async {
                    await _chooseUnit(line);
                    refreshOverlay?.call();
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(line.unit.code),
                ),
              const Spacer(),
              if (line.product.trackingMode != 'serial') ...[
                _quantityButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Reduce quantity',
                  onPressed: () {
                    _qty(line, -1);
                    refreshOverlay?.call();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    quantityText,
                    style: const TextStyle(
                      color: Color(0xFF14233B),
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                _quantityButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Increase quantity',
                  onPressed: () {
                    _qty(line, 1);
                    refreshOverlay?.call();
                  },
                ),
              ],
              const SizedBox(width: 3),
              _quantityButton(
                icon: Icons.close_rounded,
                tooltip: 'Remove item',
                onPressed: () {
                  setState(() => cart.remove(line));
                  refreshOverlay?.call();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(29),
          maximumSize: const Size.square(29),
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFF3F6FA),
          foregroundColor: const Color(0xFF506176),
        ),
        icon: Icon(icon, size: 16),
      );


  Future<void> _payFromCartPage() async {
    Navigator.of(context).maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await checkout();
  }

  Widget _mobileCartBar() {
    final quantity = cart.fold<double>(0, (sum, line) => sum + line.quantity);
    final quantityText = quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      color: const Color(0xFFFAFCFE),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: cart.isEmpty ? null : _openCartPage,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: Text(
                cart.isEmpty
                    ? 'Cart empty'
                    : '$quantityText items  •  ${money(total)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                alignment: Alignment.centerLeft,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: cart.isEmpty ? null : checkout,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('PAY'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 50),
              backgroundColor: const Color(0xFF14A765),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCartPage() async {
    if (cart.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, setPageState) => Scaffold(
            backgroundColor: const Color(0xFFF2F6FA),
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Order',
                    style: TextStyle(
                      color: Color(0xFF14233B),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    customer?.name ?? 'Select customer',
                    style: const TextStyle(
                      color: Color(0xFF768398),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            body: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDDE5EE)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _cartPanel(
                    compact: true,
                    refreshOverlay: () {
                      if (routeContext.mounted) {
                        setPageState(() {});
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
