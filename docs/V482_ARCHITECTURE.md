# THQ ERP v4.8.2 Architecture

## Pricing
`Customer + Product Variant + Sales Unit + Quantity + Location` → PostgreSQL pricing resolver → authoritative unit price and provenance.

Precedence: customer-specific → assigned/default price list → configured product-unit price → location price → product retail price. Quantity breaks are evaluated in the **entered sales unit**, selecting the greatest matching minimum quantity.

## Product Identification
`product_identifiers_v482` is the extensible source for barcode, QR, manufacturer, supplier, internal and alternate SKU codes. SKU remains a first-class identifier on `product_variants`. Legacy `barcode` and `part_number` compatibility fields are synchronized from active identifiers.

## Labels
Label definitions are data-driven in `label_templates_v482`. Rendering remains client-side so Windows/desktop printer selection is local to the business machine.

## Security
- Read APIs enforce tenant access.
- Pricing/identifier writes require owner or appropriate sales/inventory management permission.
- Sales are repriced by the database immediately before the proven v4.8.1 transaction engine posts the document.
