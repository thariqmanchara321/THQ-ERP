import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MaterialYardFormat {
  static final NumberFormat _cftFormatter = NumberFormat('#,##0.00');

  static String money(dynamic amount, {String currency = 'INR'}) {
    final val = _toDouble(amount);
    if (currency == 'INR' || currency == '₹') {
      return '₹${val.toStringAsFixed(2)}';
    }
    return '$currency ${val.toStringAsFixed(2)}';
  }

  static String cft(dynamic value, {bool includeUnit = true}) {
    final val = _toDouble(value);
    final formatted = _cftFormatter.format(val);
    return includeUnit ? '$formatted CFT' : formatted;
  }

  static String quantity(dynamic value, String unit) {
    final val = _toDouble(value);
    if ((val - val.roundToDouble()).abs() < 0.000001) {
      return '${val.toStringAsFixed(0)} $unit';
    }
    return '${val.toStringAsFixed(2)} $unit';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0.0;
  }

  static Color statusColor(String? status) {
    switch ((status ?? 'draft').toLowerCase()) {
      case 'invoiced':
      case 'completed':
      case 'billed':
        return const Color(0xFF00875A); // Green
      case 'confirmed':
      case 'unbilled':
        return const Color(0xFF0052CC); // Blue
      case 'rate_pending':
        return const Color(0xFFFF8B00); // Amber
      case 'cancelled':
        return const Color(0xFFDE350B); // Red
      case 'draft':
      default:
        return const Color(0xFFFF9900); // Orange
    }
  }

  static String statusLabel(String? status) {
    switch ((status ?? 'draft').toLowerCase()) {
      case 'invoiced':
      case 'billed':
        return 'BILLED';
      case 'confirmed':
        return 'CONFIRMED';
      case 'unbilled':
        return 'UNBILLED';
      case 'rate_pending':
        return 'RATE PENDING';
      case 'cancelled':
        return 'CANCELLED';
      case 'draft':
      default:
        return 'DRAFT';
    }
  }

  static Color workflowColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'billed':
      case 'invoiced':
        return const Color(0xFF00875A);
      case 'unbilled':
      case 'confirmed':
        return const Color(0xFF0052CC);
      case 'rate_pending':
        return const Color(0xFFFF8B00);
      case 'needs_action':
        return const Color(0xFF0052CC);
      case 'cancelled':
        return const Color(0xFFDE350B);
      case 'draft':
      default:
        return const Color(0xFF6B778C);
    }
  }

  static String workflowLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'billed':
        return 'BILLED';
      case 'unbilled':
        return 'UNBILLED';
      case 'rate_pending':
        return 'RATE PENDING';
      case 'needs_action':
        return 'NEEDS ACTION';
      case 'cancelled':
        return 'CANCELLED';
      case 'draft':
      default:
        return 'DRAFT';
    }
  }
}
