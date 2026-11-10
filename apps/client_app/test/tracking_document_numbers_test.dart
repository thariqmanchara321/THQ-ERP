import 'package:client_app/models/purchase.dart';
import 'package:client_app/models/purchase_detail.dart';
import 'package:client_app/models/sale.dart';
import 'package:client_app/models/sale_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sale tracking document number cleaning', () {
    test('cleans raw terminal prefixes from invoice numbers', () {
      expect(
        Sale.cleanTrackingNumber('MAIN-CLIENT-6EB1D9AE-INV-000001'),
        'INV-000001',
      );
      expect(
        Sale.cleanTrackingNumber('MAIN-CLIENT-6EB1D9AE-SAL-000001'),
        'SAL-000001',
      );
      expect(
        Sale.cleanTrackingNumber('MAIN-INV-000042'),
        'INV-000042',
      );
      expect(
        Sale.cleanTrackingNumber('sal- 00001'),
        'SAL-00001',
      );
      expect(
        Sale.cleanTrackingNumber('SAL-000001'),
        'SAL-000001',
      );
    });

    test('Sale.fromMap prioritizes sale_number and strips terminal details', () {
      final sale = Sale.fromMap({
        'sale_id': '3b607422-bbe2-4cc9-b23b-e3d679212014',
        'sale_number': 'SAL-000001',
        'invoice_number': 'MAIN-CLIENT-6EB1D9AE-INV-000001',
        'customer_id': 'cust-1',
        'customer_name': 'MUSADDIK',
        'sale_date': '2026-10-12',
        'grand_total': 5220.0,
        'paid_amount': 5220.0,
        'balance_due': 0.0,
        'payment_status': 'paid',
        'cost_total': 5040.0,
        'gross_profit': 180.0,
        'status': 'posted',
      });

      expect(sale.number, 'SAL-000001');
      expect(sale.rawInvoiceNumber, 'MAIN-CLIENT-6EB1D9AE-INV-000001');
    });

    test('Sale.fromMap cleans terminal invoice_number when sale_number is omitted', () {
      final sale = Sale.fromMap({
        'sale_id': '3b607422-bbe2-4cc9-b23b-e3d679212014',
        'invoice_number': 'MAIN-CLIENT-6EB1D9AE-INV-000001',
        'customer_id': 'cust-1',
        'customer_name': 'MUSADDIK',
        'sale_date': '2026-10-12',
        'grand_total': 5220.0,
        'paid_amount': 5220.0,
        'balance_due': 0.0,
        'payment_status': 'paid',
        'cost_total': 5040.0,
        'gross_profit': 180.0,
        'status': 'posted',
      });

      expect(sale.number, 'INV-000001');
    });

    test('SaleDetail.fromMap formats clean saleNumber', () {
      final detail = SaleDetail.fromMap({
        'sale': {
          'sale_id': 'sale-1',
          'sale_number': 'SAL-000001',
          'invoice_number': 'MAIN-CLIENT-6EB1D9AE-INV-000001',
          'customer_id': 'cust-1',
          'customer_name': 'MUSADDIK',
          'sale_date': '2026-10-12',
          'status': 'posted',
          'subtotal': 5000.0,
          'discount_total': 0.0,
          'taxable_total': 5000.0,
          'tax_total': 220.0,
          'additional_charges': 0.0,
          'grand_total': 5220.0,
          'cost_total': 5040.0,
          'gross_profit': 180.0,
        },
        'items': [],
        'payments': [],
      });

      expect(detail.saleNumber, 'SAL-000001');
    });
  });

  group('Purchase tracking document number cleaning', () {
    test('cleans raw terminal prefixes from purchase numbers', () {
      expect(
        Purchase.cleanTrackingNumber('MAIN-CLIENT-6EB1D9AE-PUR-000001'),
        'PUR-000001',
      );
      expect(
        Purchase.cleanTrackingNumber('MAIN-PUR-000002'),
        'PUR-000002',
      );
      expect(
        Purchase.cleanTrackingNumber('pur- 00001'),
        'PUR-00001',
      );
      expect(
        Purchase.cleanTrackingNumber('PUR-000003'),
        'PUR-000003',
      );
    });

    test('Purchase.fromMap prioritizes purchase_number and strips terminal details', () {
      final purchase = Purchase.fromMap({
        'purchase_id': '2086c33a-2cf1-472f-b868-36e3a67cf485',
        'purchase_number': 'PUR-000001',
        'invoice_number': 'MAIN-CLIENT-6EB1D9AE-PUR-000001',
        'supplier_id': 'supp-1',
        'supplier_name': 'TENZO SERVICE',
        'supplier_invoice_number': '512873f2-ddd4-4a99-aa42-f9f7a56a9966',
        'purchase_date': '2026-10-13',
        'grand_total': 34860.0,
        'paid_amount': 0.0,
        'balance_due': 34860.0,
        'payment_status': 'unpaid',
        'status': 'posted',
      });

      expect(purchase.number, 'PUR-000001');
      expect(purchase.rawInvoiceNumber, 'MAIN-CLIENT-6EB1D9AE-PUR-000001');
      expect(
        purchase.supplierInvoiceNumber,
        '512873f2-ddd4-4a99-aa42-f9f7a56a9966',
      );
    });

    test('Purchase.fromMap cleans terminal invoice_number when purchase_number is omitted', () {
      final purchase = Purchase.fromMap({
        'purchase_id': '2086c33a-2cf1-472f-b868-36e3a67cf485',
        'invoice_number': 'MAIN-CLIENT-6EB1D9AE-PUR-000001',
        'supplier_id': 'supp-1',
        'supplier_name': 'TENZO SERVICE',
        'supplier_invoice_number': '512873f2-ddd4-4a99-aa42-f9f7a56a9966',
        'purchase_date': '2026-10-13',
        'grand_total': 34860.0,
        'paid_amount': 0.0,
        'balance_due': 34860.0,
        'payment_status': 'unpaid',
        'status': 'posted',
      });

      expect(purchase.number, 'PUR-000001');
    });

    test('PurchaseDetail.fromMap formats clean purchaseNumber', () {
      final detail = PurchaseDetail.fromMap({
        'purchase': {
          'purchase_id': 'pur-1',
          'purchase_number': 'PUR-000001',
          'invoice_number': 'MAIN-CLIENT-6EB1D9AE-PUR-000001',
          'supplier_id': 'supp-1',
          'supplier_name': 'TENZO SERVICE',
          'purchase_date': '2026-10-13',
          'status': 'posted',
          'grand_total': 34860.0,
          'paid_amount': 0.0,
          'balance_due': 34860.0,
        },
        'items': [],
        'payments': [],
      });

      expect(detail.purchaseNumber, 'PUR-000001');
    });
  });
}
