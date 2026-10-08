import 'dart:io';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/sale_detail.dart';
import 'package:client_app/services/invoice_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = ClientSession(
  business: ClientBusiness(
    id: 'fixture',
    membershipId: 'owner',
    name: 'Invoice Test Store',
    slug: 'fixture',
    businessType: 'material_yard',
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
);

void main() {
  for (final mode in ['non_gst', 'regular', 'composition']) {
    for (final paper in ['a4', '80mm', '58mm']) {
      test('$mode invoice renders on $paper with a minimal template', () async {
        final registered = mode != 'non_gst';
        final tax = mode == 'regular' ? 36 : 0;
        final sale = SaleDetail.fromMap({
          'sale': {
            'sale_id': 'fixture',
            'sale_number': 'INV-2026-001',
            'customer_id': 'customer',
            'customer_name': 'Saved Customer',
            'customer_address_line1': 'Saved customer address',
            'sale_date': '2026-10-04',
            'status': 'posted',
            'subtotal': 200,
            'taxable_total': 200,
            'tax_total': tax,
            'grand_total': 200 + tax,
          },
          'items': [
            {
              'item_id': 'item',
              'variant_id': 'material',
              'product_name': 'Saved material description',
              'sku': 'STONE',
              'unit_code': 'CFT',
              'quantity': 2,
              'unit_price': 100,
              'taxable_value': 200,
              'tax_rate': 99,
              'hsn_sac': 'STALE',
              'tax_amount': tax,
              'line_total': 200 + tax,
            },
          ],
          'gst': {
            'authoritative': true,
            'tax_mode': registered ? 'gst_registered' : 'non_gst',
            'document_class': mode == 'composition'
                ? 'bill_of_supply'
                : registered
                ? 'tax_invoice'
                : 'commercial_invoice',
            'supplier_gstin': registered ? '27AAPFU0939F1ZV' : null,
            'supplier_legal_name': registered
                ? 'Saved Registered Business'
                : null,
            'supplier_address': registered
                ? 'Saved seller address, Maharashtra'
                : null,
            'place_of_supply_code': registered ? '27' : null,
            'has_reverse_charge': false,
            'taxable_total': 200,
            'cgst_total': tax / 2,
            'sgst_total': tax / 2,
            'tax_collected_total': tax,
            'lines': [
              {
                'source_line_id': 'item',
                'line_no': 1,
                'hsn_sac': '2517',
                'gst_rate': mode == 'regular' ? 18 : 0,
                'taxable_value': 200,
                'cgst': tax / 2,
                'sgst': tax / 2,
                'tax_amount': tax,
              },
            ],
          },
          'payments': [],
          'paid_amount': 0,
          'balance_due': 200 + tax,
        });
        final bytes = await InvoicePdfService().build(
          session: _session,
          sale: sale,
          paperType: paper,
          template: {
            'config': {
              'columns': ['item', 'total'],
              'show_header': false,
              'show_gstin': false,
              'show_customer': false,
              'show_address': false,
              'show_hsn': false,
              'show_tax_breakup': false,
            },
          },
          origin: const {},
          settingsOverride: const {'business.gstin': 'CURRENT-WRONG-GSTIN'},
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
        final output = Platform.environment['THQ_INVOICE_QA_DIR'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File('$output/${mode}_$paper.pdf').writeAsBytes(bytes);
        }
      });
    }
  }
}
