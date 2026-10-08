import 'package:client_app/models/sale_invoice_context.dart';
import 'package:client_app/models/sale_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'non-GST billing ignores stale product tax without changing the sale',
    () {
      final context = SaleInvoiceContext.fromMap({'tax_mode': 'non_gst'});
      final item = <String, dynamic>{
        'variant_id': 'material',
        'quantity': 2,
        'unit_price': 100,
        'discount_amount': 10,
        'tax_rate': 18,
        'thq_tax_override_v630': {'gst_rate': 5},
        'batches': [
          {'batch_id': 'batch', 'quantity': 2},
        ],
      };
      final clean = context.saleItems([item]).single;
      expect(clean['tax_rate'], 0);
      expect(clean.containsKey('thq_tax_override_v630'), false);
      expect(clean['quantity'], 2);
      expect(clean['unit_price'], 100);
      expect(clean['discount_amount'], 10);
      expect(clean['batches'], item['batches']);
      expect(item['tax_rate'], 18);
      expect(item.containsKey('thq_tax_override_v630'), true);
    },
  );

  test('registered billing keeps the GST adjustment for server validation', () {
    final context = SaleInvoiceContext.fromMap({'tax_mode': 'gst_registered'});
    final item = <String, dynamic>{
      'tax_rate': 18,
      'thq_tax_override_v630': {'gst_rate': 5},
    };
    expect(context.saleItems([item]).single, item);
    expect(context.gstApplicable, true);
  });

  test(
    'unknown registration and a different confirmed customer fail closed',
    () {
      expect(
        () => SaleInvoiceContext.fromMap({'tax_mode': 'unconfigured'}),
        throwsStateError,
      );
      final context = SaleInvoiceContext.fromMap({
        'tax_mode': 'non_gst',
        'locked_customer_id': 'load-customer',
      });
      context.checkCustomer('load-customer');
      expect(() => context.checkCustomer('another-customer'), throwsStateError);
    },
  );

  test('saved billing mode determines the legal invoice heading', () {
    SaleGstDetail detail(String mode, String documentClass) =>
        SaleGstDetail.fromMap({
          'authoritative': true,
          'tax_mode': mode,
          'document_class': documentClass,
          'supplier_gstin': '27AAPFU0939F1ZV',
          'has_reverse_charge': true,
        });
    expect(detail('non_gst', 'commercial_invoice').invoiceTitle, 'INVOICE');
    expect(detail('gst_registered', 'tax_invoice').invoiceTitle, 'TAX INVOICE');
    expect(
      detail('gst_registered', 'bill_of_supply').invoiceTitle,
      'BILL OF SUPPLY',
    );
    expect(detail('gst_registered', 'tax_invoice').hasReverseCharge, true);
    expect(
      detail('gst_registered', 'tax_invoice').supplierGstin,
      '27AAPFU0939F1ZV',
    );
  });
}
