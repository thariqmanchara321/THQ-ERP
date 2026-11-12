import 'dart:async';
import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../components/thq_buttons.dart';
import '../components/thq_dialog.dart';

/// Fullscreen mobile scanning interface that pairs a phone with a desktop THQ application
/// and wirelessly transmits validated, check-digit-verified barcodes to the desktop in real time.
class ThqMobileWirelessScannerScreen extends StatefulWidget {
  /// The active tenant ID of the signed-in mobile user.
  final String tenantId;

  /// Human-readable device identifier for this phone (e.g. "Galaxy S22").
  final String deviceName;

  /// Unique hardware or installation UUID of this mobile device.
  final String deviceId;

  /// Optional assigned location / store ID of this mobile operator.
  final String? locationId;

  /// Optional pre-configured wireless transport. If omitted, uses [SupabaseRealtimeScannerTransport].
  final WirelessScannerTransport? transport;

  /// Optional pre-configured pairing payload (e.g., if paired via deep-link or manual input).
  final WirelessScannerPairingPayload? initialPayload;

  const ThqMobileWirelessScannerScreen({
    super.key,
    required this.tenantId,
    this.locationId,
    required this.deviceName,
    required this.deviceId,
    this.transport,
    this.initialPayload,
  });

  @override
  State<ThqMobileWirelessScannerScreen> createState() =>
      _ThqMobileWirelessScannerScreenState();
}

class _ThqMobileWirelessScannerScreenState
    extends State<ThqMobileWirelessScannerScreen> {
  late WirelessScannerTransport _transport;
  bool _ownsTransport = false;

  // Pairing & Connection State
  WirelessScannerPairingPayload? _payload;
  WirelessScannerState _connectionState = WirelessScannerState.disconnected;
  StreamSubscription<WirelessScannerState>? _stateSub;
  StreamSubscription<WirelessScanAck>? _ackSub;

  // Camera & Scanning State
  MobileScannerController? _cameraController;
  bool _isTorchOn = false;
  double _zoomFactor = 0.0;
  bool _isContinuousMode = true;
  bool _hasScannedRecently = false;
  String? _errorMessage;
  String? _scanWarningMessage;
  Timer? _scanWarningTimer;
  Timer? _scanCooldownTimer;
  final Map<String, Timer> _pendingAckTimers = {};

  // Scan History & Last ACK
  final List<WirelessScanHistoryItem> _scanHistory = [];
  WirelessScanAck? _lastAck;

  bool get _isDesktopWithoutCamera {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    if (widget.transport != null) {
      _transport = widget.transport!;
      _ownsTransport = false;
    } else {
      _transport = SupabaseRealtimeScannerTransport();
      _ownsTransport = true;
    }

    _stateSub = _transport.stateStream.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });

    _ackSub = _transport.incomingAcks.listen(_handleIncomingAck);

    if (widget.initialPayload != null) {
      _connectToDesktop(widget.initialPayload!);
    }
    if (!_isDesktopWithoutCamera) {
      _initCamera();
    }
  }

  void _initCamera() {
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  Future<void> _connectToDesktop(WirelessScannerPairingPayload payload) async {
    // Tenant check
    if (payload.tenantId.isNotEmpty &&
        widget.tenantId.isNotEmpty &&
        payload.tenantId != widget.tenantId) {
      setState(() {
        _errorMessage =
            'Tenant mismatch: This QR belongs to a different business organization.';
      });
      return;
    }

    // Location check (Phase 13 hardening)
    if (payload.locationId != null &&
        payload.locationId!.isNotEmpty &&
        widget.locationId != null &&
        widget.locationId!.isNotEmpty &&
        payload.locationId != widget.locationId) {
      setState(() {
        _errorMessage =
            'Location mismatch: This workstation belongs to a different store or warehouse location.';
      });
      return;
    }

    if (payload.isExpired) {
      setState(() {
        _errorMessage =
            'Pairing session has expired. Please regenerate the QR on desktop.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _connectionState = WirelessScannerState.pairingPending;
    });

    final success = await _transport.joinAsScanner(
      payload: payload,
      deviceId: widget.deviceId,
      deviceName: widget.deviceName,
      currentTenantId: widget.tenantId,
      currentLocationId: widget.locationId,
    );

    if (success && mounted) {
      setState(() {
        _payload = payload;
        _connectionState = WirelessScannerState.connected;
      });
      HapticFeedback.heavyImpact();
    } else if (mounted) {
      setState(() {
        _errorMessage =
            'Failed to establish connection with desktop workstation.';
      });
    }
  }

  void _showScanWarning(String warning) {
    _scanWarningTimer?.cancel();
    setState(() {
      _scanWarningMessage = warning;
    });
    _scanWarningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _scanWarningMessage = null);
      }
    });
  }

  void _handleIncomingAck(WirelessScanAck ack) {
    if (!mounted) return;

    // 1. Cancel pending timeout timer for this messageId
    _pendingAckTimers.remove(ack.messageId)?.cancel();

    // 2. Cryptographic signature check: verify handshake signature on ACK packet
    if (_payload != null && !ack.verifySignature(_payload!.handshakeSecret)) {
      return;
    }

    setState(() {
      _lastAck = ack;
      final index = _scanHistory.indexWhere((h) => h.messageId == ack.messageId);
      if (index != -1) {
        final item = _scanHistory[index];
        final isCodeMatching = ack.receivedCode.isEmpty || ack.receivedCode == item.rawCode;
        if (ack.success && isCodeMatching) {
          item.status = WirelessScanDeliveryStatus.delivered;
        } else {
          item.status = WirelessScanDeliveryStatus.failed;
          item.errorMessage = ack.errorMessage ?? (isCodeMatching ? 'Desktop rejected scan' : 'Fidelity error: received code mismatch');
        }
        item.ack = ack;
      }
    });

    if (ack.isDuplicate) {
      _showScanWarning('Duplicate scan suppressed on desktop');
      HapticFeedback.lightImpact();
    } else if (ack.success) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScannedRecently) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isEmpty) continue;

      if (_connectionState != WirelessScannerState.connected) {
        // We are in Pairing Mode: Look for pairing QR code
        _handlePairingScan(raw);
        break;
      } else {
        // We are in Active Scan Mode: Verify camera accuracy and transmit
        final format = SmartBarcodeFormat.fromRawName(barcode.format.name);
        final accuracy = BarcodeAccuracyVerifier.verify(
          rawValue: raw,
          format: format,
        );

        if (!accuracy.isValid) {
          // Check digit failed or corrupted read; notify user immediately
          _showScanWarning('Corrupted scan rejected: ${accuracy.rejectionReason}');
          HapticFeedback.heavyImpact();
          continue;
        }

        _handleProductScan(accuracy.rawCode, format);
        break;
      }
    }
  }

  void _handlePairingScan(String rawPayload) {
    try {
      final payload = WirelessScannerPairingPayload.fromQrString(rawPayload);
      _connectToDesktop(payload);
    } catch (e) {
      setState(() {
        _errorMessage =
            'Unrecognized pairing QR. Point camera at the QR code displayed on THQ Desktop.';
      });
    }
  }

  Future<void> _handleProductScan(
      String rawCode, SmartBarcodeFormat format) async {
    if (_payload == null) return;

    setState(() {
      _hasScannedRecently = true;
    });
    HapticFeedback.selectionClick();

    final scanMessage = WirelessScanMessage.create(
      sessionId: _payload!.sessionId,
      tenantId: widget.tenantId,
      senderDeviceId: widget.deviceId,
      senderDeviceName: widget.deviceName,
      rawCode: rawCode,
      format: format,
      handshakeSecret: _payload!.handshakeSecret,
    );

    final historyItem = WirelessScanHistoryItem(
      messageId: scanMessage.messageId,
      rawCode: rawCode,
      format: format,
      status: WirelessScanDeliveryStatus.pending,
      timestamp: DateTime.now(),
    );

    setState(() {
      _scanHistory.insert(0, historyItem);
    });

    final delivered = await _transport.sendScan(scanMessage);
    if (mounted) {
      setState(() {
        if (!delivered) {
          historyItem.status = WirelessScanDeliveryStatus.failed;
          historyItem.errorMessage = 'Network transmission failed';
        }
      });
    }

    if (delivered) {
      // 5-second timeout for cryptographically signed desktop acknowledgement
      final timer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            final idx = _scanHistory.indexWhere((h) => h.messageId == scanMessage.messageId);
            if (idx != -1 && _scanHistory[idx].status == WirelessScanDeliveryStatus.pending) {
              _scanHistory[idx].status = WirelessScanDeliveryStatus.failed;
              _scanHistory[idx].errorMessage = 'Desktop acknowledgement timed out (5s)';
            }
          });
        }
      });
      _pendingAckTimers[scanMessage.messageId] = timer;
    }

    final cooldown = _isContinuousMode
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 1500);

    _scanCooldownTimer?.cancel();
    _scanCooldownTimer = Timer(cooldown, () {
      if (mounted) setState(() => _hasScannedRecently = false);
    });
  }

  Future<void> _showManualEntryDialog() async {
    final controller = TextEditingController();
    await showThqDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Barcode Entry'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode or SKU',
            hintText: 'e.g. 8901234567890',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          onSubmitted: (val) {
            Navigator.of(ctx).pop();
            if (val.trim().isNotEmpty) {
              _handleProductScan(val.trim(), SmartBarcodeFormat.unknown);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ThqPrimaryButton(
            label: 'Send to PC',
            onPressed: () {
              Navigator.of(ctx).pop();
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                _handleProductScan(val, SmartBarcodeFormat.unknown);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _unpair() async {
    final confirmed = await showThqDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Scanner?'),
        content: const Text(
          'Are you sure you want to disconnect from the desktop workstation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _transport.unpair();
      setState(() {
        _payload = null;
        _connectionState = WirelessScannerState.disconnected;
        _lastAck = null;
      });
    }
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.toggleTorch();
      setState(() => _isTorchOn = !_isTorchOn);
    } catch (_) {}
  }

  Future<void> _cycleZoom() async {
    if (_cameraController == null) return;
    try {
      final next = switch (_zoomFactor) {
        0.0 => 0.5,
        0.5 => 1.0,
        _ => 0.0,
      };
      await _cameraController!.setZoomScale(next);
      setState(() => _zoomFactor = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.switchCamera();
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanWarningTimer?.cancel();
    _scanCooldownTimer?.cancel();
    for (final timer in _pendingAckTimers.values) {
      timer.cancel();
    }
    _pendingAckTimers.clear();
    _stateSub?.cancel();
    _ackSub?.cancel();
    _cameraController?.dispose();
    if (_ownsTransport) {
      _transport.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _connectionState == WirelessScannerState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Camera Viewfinder
            if (_cameraController != null)
              MobileScanner(
                controller: _cameraController!,
                onDetect: _onDetect,
              )
            else
              Container(
                color: const Color(0xFF0F172A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.camera_alt_outlined
                            : Icons.qr_code_scanner,
                        color: Colors.white24,
                        size: 64,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isConnected
                            ? 'Ready to scan barcodes'
                            : 'Align desktop pairing QR in frame',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            // 2. Viewfinder Target Frame
            Center(
              child: Container(
                width: isConnected ? 280 : 250,
                height: isConnected ? 180 : 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isConnected ? Colors.greenAccent : Colors.white70,
                    width: 2.5,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected ? Colors.green : Colors.blue)
                          .withAlpha(40),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Top Header Bar with Live Status
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildTopHeader(theme, isConnected),
            ),

            // 4. Desktop Product ACK Live Banner (Floating)
            if (isConnected && _lastAck != null)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: _buildAckBanner(theme, _lastAck!),
              ),

            // 5. Warning / Error Banner (if any)
            if (_scanWarningMessage != null)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: _buildWarningBanner(theme, _scanWarningMessage!),
              )
            else if (_errorMessage != null)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: _buildErrorBanner(theme, _errorMessage!),
              ),

            // 6. Bottom Controls Bar
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildBottomControls(theme, isConnected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(ThemeData theme, bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isConnected
                      ? (_payload?.hostDeviceName ?? 'Desktop Connected')
                      : 'Wireless Scanner Pairing',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  isConnected
                      ? 'Point camera at product barcodes'
                      : 'Scan QR on THQ Desktop screen to pair',
                  style: TextStyle(
                    color: isConnected ? Colors.greenAccent : Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isConnected) ...[
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              tooltip: 'Scan History',
              onPressed: _showHistorySheet,
            ),
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              tooltip: 'Disconnect',
              onPressed: _unpair,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAckBanner(ThemeData theme, WirelessScanAck ack) {
    final isDup = ack.isDuplicate;
    final bgColor = !ack.success
        ? Colors.red.withAlpha(230)
        : (isDup
            ? const Color(0xFF1E3A8A).withAlpha(240)
            : const Color(0xFF065F46).withAlpha(240));

    final titleText = !ack.success
        ? 'Scan Not Resolved'
        : (isDup
            ? 'Duplicate Scan Suppressed'
            : (ack.productName ?? 'Product Verified'));

    final icon = !ack.success
        ? Icons.error_outline
        : (isDup ? Icons.filter_none : Icons.check_circle);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (ack.updatedQuantity != null)
                  Text(
                    'Quantity in cart: ${ack.updatedQuantity}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  )
                else if (isDup)
                  const Text(
                    'Rapid duplicate scan filtered safely',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 16),
            onPressed: () => setState(() => _lastAck = null),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(ThemeData theme, String warning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withAlpha(240),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 16),
            onPressed: () => setState(() => _scanWarningMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withAlpha(230),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 16),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(ThemeData theme, bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(190),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Torch
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? Colors.amber : Colors.white,
            ),
            tooltip: 'Flashlight',
            onPressed: _toggleTorch,
          ),

          // Zoom
          IconButton(
            icon: Icon(
              _zoomFactor == 0.0
                  ? Icons.zoom_in
                  : (_zoomFactor == 0.5 ? Icons.zoom_out : Icons.zoom_out_map),
              color: Colors.white,
            ),
            tooltip: 'Zoom ${_zoomFactor == 0.0 ? "1x" : (_zoomFactor == 0.5 ? "2x" : "3x")}',
            onPressed: _cycleZoom,
          ),

          // Flip Camera
          IconButton(
            icon: const Icon(Icons.flip_camera_android, color: Colors.white),
            tooltip: 'Flip Camera',
            onPressed: _switchCamera,
          ),

          if (isConnected) ...[
            // Continuous vs Single mode
            IconButton(
              icon: Icon(
                _isContinuousMode ? Icons.repeat : Icons.repeat_one,
                color: _isContinuousMode ? Colors.greenAccent : Colors.white70,
              ),
              tooltip: _isContinuousMode
                  ? 'Continuous Mode (Active)'
                  : 'Single Scan Mode',
              onPressed: () {
                setState(() => _isContinuousMode = !_isContinuousMode);
              },
            ),

            // Manual Entry
            IconButton(
              icon: const Icon(Icons.keyboard, color: Colors.white),
              tooltip: 'Manual Barcode Entry',
              onPressed: _showManualEntryDialog,
            ),
          ],
        ],
      ),
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Session Scan History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_scanHistory.length} scans',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 20),
              if (_scanHistory.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      'No barcodes scanned yet this session.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _scanHistory.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _scanHistory[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          item.status == WirelessScanDeliveryStatus.delivered
                              ? Icons.check_circle
                              : (item.status == WirelessScanDeliveryStatus.pending
                                  ? Icons.access_time
                                  : Icons.error),
                          color: item.status == WirelessScanDeliveryStatus.delivered
                              ? Colors.greenAccent
                              : (item.status ==
                                      WirelessScanDeliveryStatus.pending
                                  ? Colors.amber
                                  : Colors.redAccent),
                          size: 20,
                        ),
                        title: Text(
                          item.rawCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          item.ack?.productName ??
                              '${item.format.displayName} • ${item.status.name}',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                        trailing: Text(
                          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
