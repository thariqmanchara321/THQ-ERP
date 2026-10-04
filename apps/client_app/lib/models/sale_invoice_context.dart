/// Server-resolved billing mode for the invoice date and selected location.
/// Unknown or incomplete registration never silently becomes a non-GST sale.
class SaleInvoiceContext {
  final String taxMode;
  final String? lockedCustomerId;

  const SaleInvoiceContext({required this.taxMode, this.lockedCustomerId});

  bool get gstApplicable => taxMode == 'gst_registered';

  factory SaleInvoiceContext.fromMap(Map<String, dynamic> map) {
    final mode = map['tax_mode']?.toString();
    if (mode != 'non_gst' && mode != 'gst_registered') {
      throw StateError('Complete the business GST setup before billing.');
    }
    return SaleInvoiceContext(
      taxMode: mode!,
      lockedCustomerId: map['locked_customer_id']?.toString(),
    );
  }

  List<Map<String, dynamic>> saleItems(List<Map<String, dynamic>> items) =>
      items
          .map((item) {
            final copy = Map<String, dynamic>.from(item);
            if (!gstApplicable) {
              copy.remove('thq_tax_override_v630');
              copy['tax_rate'] = 0;
            }
            return copy;
          })
          .toList(growable: false);

  void checkCustomer(String customerId) {
    if (lockedCustomerId != null && lockedCustomerId != customerId) {
      throw StateError(
        'Select the customer recorded on the confirmed Load Ticket.',
      );
    }
  }
}
