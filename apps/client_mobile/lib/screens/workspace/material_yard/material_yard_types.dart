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
        return const Color(0xFF00875A); // Green
      case 'confirmed':
        return const Color(0xFF0052CC); // Blue
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
        return 'INVOICED';
      case 'confirmed':
        return 'CONFIRMED';
      case 'cancelled':
        return 'CANCELLED';
      case 'draft':
      default:
        return 'DRAFT';
    }
  }
}
