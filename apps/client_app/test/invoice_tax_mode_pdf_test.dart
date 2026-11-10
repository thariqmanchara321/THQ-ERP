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

  group('Document Types: ESTIMATE vs TAX INVOICE', () {
    for (final paper in ['a4', '80mm', '58mm']) {
      test('ESTIMATE renders successfully on $paper with non-posting estimate sale', () async {
        final estimateSale = SaleDetail.fromMap({
          'sale': {
            'sale_id': 'estimate-draft',
            'sale_number': 'EST-2026-0042',
            'customer_id': 'cust-01',
            'customer_name': 'Prospective Client',
            'customer_address_line1': '123 Market Street',
            'sale_date': '2026-10-13',
            'status': 'estimate',
            'subtotal': 500,
            'taxable_total': 500,
            'tax_total': 0,
            'grand_total': 500,
          },
          'items': [
            {
              'item_id': 'item-1',
              'variant_id': 'mat-1',
              'product_name': 'Steel Rod 12mm',
              'sku': 'ROD12',
              'unit_code': 'KG',
              'quantity': 10,
              'unit_price': 50,
              'taxable_value': 500,
              'tax_rate': 0,
              'tax_amount': 0,
              'line_total': 500,
            },
          ],
          'gst': null,
          'payments': [],
          'paid_amount': 0,
          'balance_due': 500,
        });

        final bytes = await InvoicePdfService().build(
          session: _session,
          sale: estimateSale,
          paperType: paper,
          template: {
            'config': {
              'document_type': 'estimate',
              'columns': ['item', 'total'],
              'show_header': true,
              'show_customer': true,
            },
          },
          origin: const {},
        );

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });

      test('TAX INVOICE renders successfully on $paper with tax_invoice document_type', () async {
        final taxInvoiceSale = SaleDetail.fromMap({
          'sale': {
            'sale_id': 'inv-01',
            'sale_number': 'INV-2026-0042',
            'customer_id': 'cust-01',
            'customer_name': 'Registered Buyer',
            'customer_address_line1': '456 Industrial Zone',
            'sale_date': '2026-10-13',
            'status': 'posted',
            'subtotal': 1000,
            'taxable_total': 1000,
            'tax_total': 180,
            'grand_total': 1180,
          },
          'items': [
            {
              'item_id': 'item-1',
              'variant_id': 'mat-1',
              'product_name': 'Crushed Aggregate 20mm',
              'sku': 'AGG20',
              'unit_code': 'TON',
              'quantity': 2,
              'unit_price': 500,
              'taxable_value': 1000,
              'tax_rate': 18,
              'tax_amount': 180,
              'line_total': 1180,
            },
          ],
          'gst': {
            'authoritative': true,
            'tax_mode': 'gst_registered',
            'document_class': 'tax_invoice',
            'supplier_gstin': '27AAPFU0939F1ZV',
            'supplier_legal_name': 'Invoice Test Store',
            'supplier_address': 'Saved seller address, Maharashtra',
            'place_of_supply_code': '27',
            'has_reverse_charge': false,
            'taxable_total': 1000,
            'cgst_total': 90,
            'sgst_total': 90,
            'tax_collected_total': 180,
            'lines': [
              {
                'source_line_id': 'item-1',
                'line_no': 1,
                'hsn_sac': '2517',
                'gst_rate': 18,
                'taxable_value': 1000,
                'cgst': 90,
                'sgst': 90,
                'tax_amount': 180,
              },
            ],
          },
          'payments': [
            {
              'payment_id': 'pay-1',
              'amount': 1180,
              'payment_method': 'cash',
              'paid_at': '2026-10-13T10:00:00Z',
            },
          ],
          'paid_amount': 1180,
          'balance_due': 0,
        });

        final bytes = await InvoicePdfService().build(
          session: _session,
          sale: taxInvoiceSale,
          paperType: paper,
          template: {
            'config': {
              'document_type': 'tax_invoice',
              'columns': ['item', 'total'],
              'show_header': true,
              'show_customer': true,
            },
          },
          origin: const {},
        );

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });
    }
  });

  group('Invoice Number Cleaning & Company Name Styling', () {
    test('renders PDF cleanly with terminal-prefixed invoice number and custom styled company name', () async {
      final sale = SaleDetail.fromMap({
        'sale': {
          'sale_id': 'fixture-sale-1',
          'sale_number': 'SAL-2026-9999',
          'customer_id': 'cust-1',
          'customer_name': 'Commercial Buyer Ltd',
          'sale_date': '2026-10-13',
          'status': 'posted',
          'subtotal': 1000,
          'taxable_total': 1000,
          'tax_total': 180,
          'grand_total': 1180,
        },
        'items': [
          {
            'item_id': 'item-1',
            'product_name': 'Granite Aggregate 40mm',
            'sku': 'GRA40',
            'unit_code': 'TON',
            'quantity': 2,
            'unit_price': 500,
            'taxable_value': 1000,
            'tax_rate': 18,
            'tax_amount': 180,
            'line_total': 1180,
          },
        ],
        'gst': {
          'authoritative': true,
          'tax_mode': 'gst_registered',
          'document_class': 'tax_invoice',
          'supplier_gstin': '27AAPFU0939F1ZV',
          'supplier_legal_name': 'Default Registered Business',
          'taxable_total': 1000,
          'cgst_total': 90,
          'sgst_total': 90,
          'tax_collected_total': 180,
          'lines': [],
        },
        'payments': [],
        'paid_amount': 0,
        'balance_due': 1180,
      });

      // Terminal-specific raw invoice number with store, device, and seq
      final originWithTerminalNumber = {
        'invoice_number': 'MAIN-CLIENT-6EB1D9AE-INV-000001',
        'location_name': 'TENZO TRADERS - Main',
      };

      final pdfBytes = await InvoicePdfService().build(
        session: _session,
        sale: sale,
        paperType: 'a4',
        template: {
          'config': {
            'company_name': 'Customized Tenzo Holdings',
            'company_name_color': '#1E40AF',
            'company_name_size': 30,
            'company_name_bold': true,
            'company_name_italic': true,
            'company_name_uppercase': true,
            'show_branch_name': false,
            'show_erp_ref': false,
            'show_header': true,
            'show_customer': true,
          },
        },
        origin: originWithTerminalNumber,
      );

      expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
      expect(pdfBytes.length, greaterThan(1500));
    });

    test('renders 80mm roll with clean invoice number from location number', () async {
      final sale = SaleDetail.fromMap({
        'sale': {
          'sale_id': 'fixture-sale-2',
          'sale_number': 'SAL-2026-0042',
          'customer_id': 'cust-2',
          'customer_name': 'Walk-in Customer',
          'sale_date': '2026-10-13',
          'status': 'posted',
          'subtotal': 500,
          'taxable_total': 500,
          'tax_total': 0,
          'grand_total': 500,
        },
        'items': [
          {
            'item_id': 'item-1',
            'product_name': 'River Sand',
            'sku': 'SAND-01',
            'unit_code': 'CFT',
            'quantity': 10,
            'unit_price': 50,
            'taxable_value': 500,
            'tax_rate': 0,
            'tax_amount': 0,
            'line_total': 500,
          },
        ],
        'gst': {
          'authoritative': false,
          'tax_mode': 'non_gst',
        },
        'payments': [],
        'paid_amount': 500,
        'balance_due': 0,
      });

      final originWithLocationNumber = {
        'invoice_number': 'MAIN-INV-000042',
        'location_name': 'Warehouse 1',
      };

      final pdfBytes = await InvoicePdfService().build(
        session: _session,
        sale: sale,
        paperType: '80mm',
        template: {
          'config': {
            'company_name': 'Sand & Stone Depot',
            'company_name_color': 'accent',
            'company_name_size': 24,
            'company_name_bold': false,
            'company_name_italic': false,
            'company_name_uppercase': false,
            'show_branch_name': false,
            'show_erp_ref': false,
            'accent': '#16A34A',
          },
        },
        origin: originWithLocationNumber,
      );

      expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
      expect(pdfBytes.length, greaterThan(1000));
    });
  });
}
