import 'dart:convert';
import 'package:flutter/material.dart';

/// Renders the tenant / business logo across all THQ ERP platforms
/// (Client Desktop, Client Mobile, POS, and Mobile POS).
///
/// Gracefully handles:
/// - Remote HTTPS/HTTP URLs
/// - Base64 data URIs (`data:image/...;base64,...`)
/// - Network failures and format errors with caller-defined fallback
class ThqBusinessLogo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? fallback;
  final Color? backgroundColor;
  final Color? borderColor;
  final BoxFit fit;
  final EdgeInsetsGeometry padding;

  const ThqBusinessLogo({
    super.key,
    this.logoUrl,
    this.size = 38,
    this.width,
    this.height,
    this.borderRadius,
    this.fallback,
    this.backgroundColor,
    this.borderColor,
    this.fit = BoxFit.contain,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width ?? size;
    final effectiveHeight = height ?? size;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(12);

    final raw = (logoUrl ?? '').trim();
    if (raw.isEmpty) {
      return _wrapFallback(effectiveWidth, effectiveHeight, effectiveRadius);
    }

    Widget imageWidget;
    if (raw.startsWith('data:image/') && raw.contains(';base64,')) {
      try {
        final b64 = raw.substring(raw.indexOf(';base64,') + 8);
        final bytes = base64Decode(b64);
        imageWidget = Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (_, _, _) => _wrapFallback(
            effectiveWidth,
            effectiveHeight,
            effectiveRadius,
          ),
        );
      } catch (_) {
        return _wrapFallback(effectiveWidth, effectiveHeight, effectiveRadius);
      }
    } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
      imageWidget = Image.network(
        raw,
        fit: fit,
        errorBuilder: (_, _, _) => _wrapFallback(
          effectiveWidth,
          effectiveHeight,
          effectiveRadius,
        ),
      );
    } else {
      return _wrapFallback(effectiveWidth, effectiveHeight, effectiveRadius);
    }

    return Container(
      width: effectiveWidth,
      height: effectiveHeight,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: effectiveRadius,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: imageWidget,
    );
  }

  Widget _wrapFallback(double w, double h, BorderRadius r) {
    if (fallback != null) {
      if (backgroundColor == null && borderColor == null) {
        return fallback!;
      }
      return Container(
        width: w,
        height: h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: r,
          border: borderColor != null ? Border.all(color: borderColor!) : null,
        ),
        alignment: Alignment.center,
        child: fallback,
      );
    }
    return Container(
      width: w,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.08),
        borderRadius: r,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.business_rounded, size: 20),
    );
  }
}
