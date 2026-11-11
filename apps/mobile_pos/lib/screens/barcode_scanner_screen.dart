import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';

/// Production Mobile POS Barcode & QR Scanner Screen.
///
/// Features:
/// 1. Reuses shared [ThqSmartScannerView] and [SmartScannerController].
/// 2. Supports both Continuous Mode (rapid sequential scans into bill) and Single Mode.
/// 3. Provides camera torch control, zoom, and camera flipping on supported mobile hardware.
/// 4. Provides manual code entry for damaged or unreadable barcodes.
/// 5. Non-intrusive live feedback overlay for added items, unknown codes, and offline misses.
/// 6. Fully backward compatible with legacy single-scan callers.
class BarcodeScannerScreen extends StatefulWidget {
  final PosSession? session;
  final List<MobileProduct>? products;
  final Future<bool> Function(String code, {ScannerSource source})? onScanCode;
  final bool initialContinuous;
  final int initialCartCount;

  const BarcodeScannerScreen({
    super.key,
    this.session,
    this.products,
    this.onScanCode,
    this.initialContinuous = true,
    this.initialCartCount = 0,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final SmartScannerController _scannerController;
  StreamSubscription<SmartScanResult>? _scanSubscription;
  late bool _isContinuous;
  late int _cartCount;

  bool _isProcessing = false;
  String? _lastFeedback;
  bool _lastFeedbackSuccess = true;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _isContinuous = widget.initialContinuous;
    _cartCount = widget.initialCartCount;

    _scannerController = SmartScannerController(
      configuration: ScannerConfiguration(
        mode: _isContinuous ? ScannerMode.continuous : ScannerMode.single,
        duplicateSuppressionDuration: const Duration(milliseconds: 1400),
        minInputLength: 1,
      ),
    );

    _scanSubscription = _scannerController.scans.listen(_handleScanResult);
    _scannerController.start();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _scanSubscription?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {required bool success}) {
    _feedbackTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _lastFeedback = message;
      _lastFeedbackSuccess = success;
    });
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _lastFeedback = null);
      }
    });
  }

  Future<void> _handleScanResult(SmartScanResult scan) async {
    final rawCode = scan.rawValue.trim();
    if (rawCode.isEmpty) return;

    // Legacy fallback: if no callback provided, pop the raw code on first scan
    if (widget.onScanCode == null) {
      if (mounted) {
        Navigator.of(context).pop(rawCode);
      }
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final success = await widget.onScanCode!(
        rawCode,
        source: scan.source,
      );

      if (!mounted) return;

      if (success) {
        setState(() => _cartCount++);
        _showFeedback('Scanned: $rawCode', success: true);
        if (!_isContinuous) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) Navigator.of(context).pop(rawCode);
        }
      } else {
        _showFeedback('Not added: $rawCode', success: false);
      }
    } catch (e) {
      if (mounted) {
        _showFeedback('Scan error: $e', success: false);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showManualEntryDialog() async {
    final code = await showThqDialog<String>(
      context: context,
      builder: (dialogCtx) => const _ManualCodeEntryDialog(),
    );

    if (code != null && code.isNotEmpty && mounted) {
      _scannerController.submitScan(
        code,
        format: SmartBarcodeFormat.unknown,
        source: ScannerSource.manual,
      );
    }
  }

  void _toggleContinuousMode() {
    setState(() {
      _isContinuous = !_isContinuous;
      _scannerController.setMode(
        _isContinuous ? ScannerMode.continuous : ScannerMode.single,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 56,
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Barcode / QR',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _isContinuous
                  ? 'Continuous Mode • $_cartCount in cart'
                  : 'Single Scan Mode',
              style: TextStyle(
                fontSize: 11,
                color: _isContinuous ? Colors.greenAccent : Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Enter code manually',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: _showManualEntryDialog,
          ),
          IconButton(
            tooltip: _isContinuous
                ? 'Switch to single scan'
                : 'Switch to continuous scan',
            icon: Icon(
              _isContinuous
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: _isContinuous ? Colors.greenAccent : Colors.white70,
            ),
            onPressed: _toggleContinuousMode,
          ),
          IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.check_circle_outline_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ThqSmartScannerView(
            controller: _scannerController,
            showControls: true,
            enableHaptic: true,
            instructionText: _isContinuous
                ? 'Align barcode inside frame to add items sequentially'
                : 'Align barcode inside frame to scan',
            onClose: () => Navigator.of(context).pop(),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_lastFeedback != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _lastFeedbackSuccess
                        ? Colors.green.shade800.withValues(alpha: 0.9)
                        : Colors.red.shade800.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _lastFeedbackSuccess
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _lastFeedback!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

class _ManualCodeEntryDialog extends StatefulWidget {
  const _ManualCodeEntryDialog();

  @override
  State<_ManualCodeEntryDialog> createState() => _ManualCodeEntryDialogState();
}

class _ManualCodeEntryDialogState extends State<_ManualCodeEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.keyboard_alt_outlined, size: 20),
          SizedBox(width: 8),
          Text('Manual Code Entry', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Barcode, SKU or serial',
          hintText: 'Enter code...',
          isDense: true,
        ),
        onSubmitted: (val) => Navigator.of(context).pop(val.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
