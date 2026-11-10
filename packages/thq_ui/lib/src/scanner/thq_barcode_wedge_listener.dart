import 'dart:async';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Callback invoked when a complete barcode is captured by the keyboard wedge listener.
typedef ThqBarcodeWedgeCallback = void Function(String barcode, ScannerSource source);

/// A widget-level listener that intercepts rapid keystrokes emitted by USB and Bluetooth
/// barcode scanners in keyboard-wedge mode without requiring explicit text field focus,
/// while safely avoiding hijacking ordinary keyboard typing.
class ThqBarcodeWedgeListener extends StatefulWidget {
  /// The widget subtree wrapped by this scanner listener.
  final Widget child;

  /// Optional controller to receive captured barcodes directly.
  final SmartScannerController? controller;

  /// Callback invoked when a complete barcode scan is decoded.
  final ThqBarcodeWedgeCallback? onScan;

  /// Whether listening is actively enabled.
  final bool enabled;

  /// Inter-character arrival latency threshold. Keystrokes arriving with delays
  /// exceeding this duration are treated as human typing and discarded from the barcode buffer.
  final Duration interCharacterTimeout;

  /// Minimum acceptable barcode length.
  final int minBarcodeLength;

  /// Maximum acceptable barcode length.
  final int maxBarcodeLength;

  /// Whether Enter (or Numpad Enter) is accepted as the scan terminator.
  final bool acceptEnterTerminator;

  /// Whether Tab is accepted as the scan terminator.
  final bool acceptTabTerminator;

  /// If true, a scan is only accepted when followed by a recognized terminator.
  final bool requireTerminator;

  /// When true, intercepts rapid scanner keystrokes even if an [EditableText] is currently focused.
  /// When false (default), active text fields receive keystrokes normally to prevent any typing interference.
  final bool interceptWhenEditableFocused;

  /// The scanner source reported when a barcode is captured (e.g. [ScannerSource.usb] or [ScannerSource.bluetooth]).
  final ScannerSource source;

  /// Optional time supplier for deterministic unit testing.
  final DateTime Function()? clockSupplier;

  const ThqBarcodeWedgeListener({
    super.key,
    required this.child,
    this.controller,
    this.onScan,
    this.enabled = true,
    this.interCharacterTimeout = const Duration(milliseconds: 45),
    this.minBarcodeLength = 3,
    this.maxBarcodeLength = 128,
    this.acceptEnterTerminator = true,
    this.acceptTabTerminator = true,
    this.requireTerminator = true,
    this.interceptWhenEditableFocused = false,
    this.source = ScannerSource.usb,
    this.clockSupplier,
  });

  @override
  State<ThqBarcodeWedgeListener> createState() => _ThqBarcodeWedgeListenerState();
}

class _ThqBarcodeWedgeListenerState extends State<ThqBarcodeWedgeListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeystrokeTime;
  Timer? _timeoutTimer;

  DateTime _now() => (widget.clockSupplier ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _timeoutTimer?.cancel();
    super.dispose();
  }

  bool _isEditableFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final context = primary.context;
    if (context == null) return false;

    var isEditable = false;
    if (context.widget is EditableText) {
      return true;
    }
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        isEditable = true;
        return false;
      }
      return true;
    });
    return isEditable;
  }

  bool _isTerminator(LogicalKeyboardKey key) {
    if (widget.acceptEnterTerminator) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        return true;
      }
    }
    if (widget.acceptTabTerminator) {
      if (key == LogicalKeyboardKey.tab) {
        return true;
      }
    }
    return false;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || !mounted) return false;

    // Only process key-down events
    if (event is! KeyDownEvent) return false;

    // Bypass completely if modifier keys (Ctrl, Alt, Meta) are pressed to respect shortcuts
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      _resetBuffer();
      return false;
    }

    // Do not hijack typing if user is currently inside an editable text field
    if (!widget.interceptWhenEditableFocused && _isEditableFocused()) {
      _resetBuffer();
      return false;
    }

    final key = event.logicalKey;
    final now = _now();

    // Check terminator
    if (_isTerminator(key)) {
      if (_buffer.isNotEmpty) {
        final elapsedSinceLast = _lastKeystrokeTime != null
            ? now.difference(_lastKeystrokeTime!)
            : Duration.zero;

        // If characters arrived rapidly (< timeout), commit barcode
        if (elapsedSinceLast <= widget.interCharacterTimeout || _buffer.length >= widget.minBarcodeLength) {
          _commitBarcode();
          return true; // Consume terminator
        } else {
          _resetBuffer();
          return false;
        }
      }
      return false;
    }

    // Read printable character from event
    final character = event.character;
    if (character == null || character.isEmpty) {
      // Non-character key (e.g. Shift, Escape, F-keys)
      if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
        return false; // Allow shift without resetting buffer
      }
      _resetBuffer();
      return false;
    }

    // Character timing check
    if (_lastKeystrokeTime != null) {
      final diff = now.difference(_lastKeystrokeTime!);
      if (diff > widget.interCharacterTimeout) {
        // Slow keystroke: human typing, not barcode scanner
        _resetBuffer();
      }
    }

    _lastKeystrokeTime = now;
    _buffer.write(character);

    // Enforce max length
    if (_buffer.length > widget.maxBarcodeLength) {
      _resetBuffer();
      return false;
    }

    // Reset buffer automatically if no subsequent character arrives within timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.interCharacterTimeout * 2, () {
      if (!widget.requireTerminator && _buffer.length >= widget.minBarcodeLength) {
        _commitBarcode();
      } else {
        _resetBuffer();
      }
    });

    return false;
  }

  void _commitBarcode() {
    _timeoutTimer?.cancel();
    final barcode = _buffer.toString().trim();
    _resetBuffer();

    if (barcode.length >= widget.minBarcodeLength && barcode.length <= widget.maxBarcodeLength) {
      widget.controller?.submitScan(
        barcode,
        source: widget.source,
      );
      widget.onScan?.call(barcode, widget.source);
    }
  }

  void _resetBuffer() {
    _buffer.clear();
    _lastKeystrokeTime = null;
    _timeoutTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
