import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../components/thq_buttons.dart';
import '../components/thq_card.dart';

/// Callback signature when a barcode or QR code is detected by [ThqSmartScannerView].
typedef ThqScanDetectedCallback = void Function(SmartScanResult result);

/// Polished, reusable camera scanning interface adhering to the THQ design system.
///
/// Automatically provides camera preview with an animated viewfinder, torch control,
/// zoom slider, camera switching, haptic feedback, and graceful fallback on desktop platforms.
class ThqSmartScannerView extends StatefulWidget {
  /// Optional [SmartScannerController] to manage state and receive scan results.
  final SmartScannerController? controller;

  /// Callback invoked when a valid barcode or QR code is detected.
  final ThqScanDetectedCallback? onScan;

  /// Optional close callback if displayed in a modal, sheet, or overlay.
  final VoidCallback? onClose;

  /// Instruction text shown above or below the viewfinder.
  final String instructionText;

  /// Whether to display camera controls (torch, zoom, camera switch).
  final bool showControls;

  /// Whether to trigger haptic feedback upon barcode detection on supported devices.
  final bool enableHaptic;

  /// Custom scanning box dimensions (width, height).
  final Size scanWindowSize;

  /// Optional custom device identifier to attach to scan results.
  final String? deviceId;

  const ThqSmartScannerView({
    super.key,
    this.controller,
    this.onScan,
    this.onClose,
    this.instructionText = 'Align barcode or QR code inside the frame',
    this.showControls = true,
    this.enableHaptic = true,
    this.scanWindowSize = const Size(260, 170),
    this.deviceId,
  });

  @override
  State<ThqSmartScannerView> createState() => _ThqSmartScannerViewState();
}

class _ThqSmartScannerViewState extends State<ThqSmartScannerView>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  late AnimationController _laserAnim;
  bool _isTorchOn = false;
  double _zoomFactor = 0.0;
  bool _hasScannedRecently = false;
  String? _lastScannedCode;
  String? _errorMessage;
  bool _isPermissionDenied = false;

  bool get _isDesktopWithoutCamera {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _laserAnim.repeat(reverse: true);
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

  @override
  void dispose() {
    _laserAnim.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScannedRecently) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) {
        final format = SmartBarcodeFormat.fromRawName(barcode.format.name);
        final accuracy = BarcodeAccuracyVerifier.verify(
          rawValue: raw,
          format: format,
        );
        if (!accuracy.isValid) {
          // Frame read had corrupted check digits or non-printable ASCII; drop glitched frame
          continue;
        }

        _handleDetectedBarcode(accuracy.sanitizedCode, barcode.format.name);
        break;
      }
    }
  }

  void _handleDetectedBarcode(String rawValue, String rawFormat) {
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _hasScannedRecently = true;
      _lastScannedCode = rawValue;
    });

    final format = SmartBarcodeFormat.fromRawName(rawFormat);

    // Forward to controller if available
    SmartScanResult? result;
    if (widget.controller != null) {
      result = widget.controller!.submitScan(
        rawValue,
        format: format,
        source: format == SmartBarcodeFormat.qrCode ? ScannerSource.qr : ScannerSource.camera,
        deviceId: widget.deviceId,
      );
    } else {
      result = SmartScanResult.valid(
        rawValue: rawValue,
        format: format,
        source: format == SmartBarcodeFormat.qrCode ? ScannerSource.qr : ScannerSource.camera,
        deviceId: widget.deviceId,
      );
    }

    if (result != null) {
      widget.onScan?.call(result);
    }

    // Cooldown before next frame read to avoid UI jitter
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _hasScannedRecently = false);
      }
    });
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isDesktopWithoutCamera) {
      return _buildDesktopFallback(context);
    }

    if (_isPermissionDenied) {
      return _buildPermissionDenied(context);
    }

    if (_errorMessage != null) {
      return _buildErrorState(context);
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Preview
          if (_cameraController != null)
            MobileScanner(
              controller: _cameraController!,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Camera error: ${error.errorCode.name}',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),

          // 2. Viewfinder Overlay
          CustomPaint(
            size: Size.infinite,
            painter: _ScannerOverlayPainter(
              windowSize: widget.scanWindowSize,
              borderColor: _hasScannedRecently ? Colors.greenAccent : colorScheme.primary,
              scanLineFraction: _laserAnim.value,
            ),
          ),

          // 3. Top Header Bar (Close button & instruction)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    if (widget.onClose != null)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close scanner',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.instructionText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Controls (Torch, Zoom, Camera Switch, Recent feedback)
          if (widget.showControls)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_lastScannedCode != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade900.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _lastScannedCode!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _toggleTorch,
                              icon: Icon(
                                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                                color: _isTorchOn ? Colors.amberAccent : Colors.white70,
                              ),
                              tooltip: 'Toggle Flashlight',
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: _cycleZoom,
                              icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                              label: Text(
                                switch (_zoomFactor) {
                                  0.0 => '1x',
                                  0.5 => '2x',
                                  _ => '3x',
                                },
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _switchCamera,
                              icon: const Icon(Icons.flip_camera_ios, color: Colors.white70),
                              tooltip: 'Switch Camera',
                            ),
                          ],
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

  Widget _buildDesktopFallback(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ThqCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, size: 36, color: Colors.blueGrey),
                const SizedBox(height: 10),
                const Text(
                  'Camera Scanner Unavailable on Desktop',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Windows desktop uses USB or Bluetooth barcode scanners in keyboard-wedge mode. '
                  'Alternatively, pair a mobile device using Phone-to-PC scanning.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(height: 12),
                  ThqPrimaryButton(
                    label: 'Close',
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ThqCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Camera Permission Denied',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please grant camera permission in your system settings to scan barcodes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ThqPrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    setState(() {
                      _isPermissionDenied = false;
                      _initCamera();
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ThqCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.amberAccent),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Scanner error',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ThqPrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _initCamera();
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter rendering the translucent dark overlay, clear central window,
/// corner brackets, and scanning laser line.
class _ScannerOverlayPainter extends CustomPainter {
  final Size windowSize;
  final Color borderColor;
  final double scanLineFraction;

  _ScannerOverlayPainter({
    required this.windowSize,
    required this.borderColor,
    required this.scanLineFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: windowSize.width,
      height: windowSize.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // 1. Dark semi-transparent mask around window
    final bgPaint = Paint()..color = const Color(0x99000000);
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    // 2. Window border
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // 3. High-visibility corner accents
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 22.0;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLen), cornerPaint);

    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLen), cornerPaint);

    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLen), cornerPaint);

    // 4. Animated scanning laser line
    final laserY = rect.top + (rect.height * scanLineFraction);
    final laserPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          borderColor.withValues(alpha: 0.0),
          borderColor.withValues(alpha: 0.8),
          borderColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(rect.left, laserY, rect.width, 2))
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(rect.left + 4, laserY), Offset(rect.right - 4, laserY), laserPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanLineFraction != scanLineFraction ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.windowSize != windowSize;
  }
}
