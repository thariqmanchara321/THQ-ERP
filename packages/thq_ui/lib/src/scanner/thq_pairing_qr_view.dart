import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Crisp, vector-based QR Code renderer for THQ ERP wireless pairing payloads.
class ThqPairingQrView extends StatelessWidget {
  /// The payload string to encode into the QR code.
  final String data;

  /// Width and height of the rendered QR code box.
  final double size;

  /// Color of the QR modules. Defaults to dark theme/on-surface color.
  final Color? foregroundColor;

  /// Background color behind the QR modules. Defaults to white for high contrast.
  final Color backgroundColor;

  /// Internal padding inside the card.
  final double padding;

  const ThqPairingQrView({
    super.key,
    required this.data,
    this.size = 200,
    this.foregroundColor,
    this.backgroundColor = Colors.white,
    this.padding = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Text('No pairing data'),
        ),
      );
    }

    final fg = foregroundColor ?? const Color(0xFF1E293B);

    return Container(
      width: size + (padding * 2),
      height: size + (padding * 2),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withAlpha(50), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _BarcodeQrPainter(
          data: data,
          foregroundColor: fg,
        ),
      ),
    );
  }
}

class _BarcodeQrPainter extends CustomPainter {
  final String data;
  final Color foregroundColor;

  _BarcodeQrPainter({
    required this.data,
    required this.foregroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final qr = Barcode.qrCode();
      final elements = qr.make(
        data,
        width: size.width,
        height: size.height,
        drawText: false,
      );

      final paint = Paint()
        ..color = foregroundColor
        ..style = PaintingStyle.fill;

      for (final el in elements) {
        if (el is BarcodeBar && el.black) {
          canvas.drawRect(
            Rect.fromLTWH(el.left, el.top, el.width, el.height),
            paint,
          );
        }
      }
    } catch (e) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'QR Error: $e',
          style: const TextStyle(color: Colors.red, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(canvas, Offset.zero);
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodeQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.foregroundColor != foregroundColor;
  }
}
