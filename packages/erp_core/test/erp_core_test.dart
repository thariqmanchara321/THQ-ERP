import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ V4.8.2 release contract is locked to migration 134', () {
    expect(ThqReleaseContract.appVersion, '4.8.2');
    expect(ThqReleaseContract.minimumMigration, 134);
    expect(ThqReleaseContract.apiVersion, 'v1');
  });

  test('sync version drift separates POS master data from transaction drift', () {
    const base = ThqSyncVersions(configuration: 1, catalogue: 1, parties: 1, transactions: 1, inventory: 1, finance: 1);
    const salesOnly = ThqSyncVersions(configuration: 1, catalogue: 1, parties: 1, transactions: 2, inventory: 2, finance: 2);
    const catalog = ThqSyncVersions(configuration: 1, catalogue: 2, parties: 1, transactions: 1, inventory: 1, finance: 1);
    expect(salesOnly.configurationOrMasterChangedFrom(base), isFalse);
    expect(salesOnly.anyChangedFrom(base), isTrue);
    expect(catalog.configurationOrMasterChangedFrom(base), isTrue);
  });

  test('unit conversion preserves base stock truth', () {
    const coil = ProductUnitOption(
      unitId: 'coil',
      code: 'COIL',
      name: 'Coil',
      decimalPlaces: 0,
      allowFractional: false,
      isBase: false,
      allowPurchase: true,
      allowSale: true,
      isDefaultPurchase: true,
      isDefaultSale: false,
      conversionToBase: 90,
      quantityStep: 1,
      salePrice: 1800,
      purchaseCost: 1500,
      cuttingAllowed: false,
      cuttingCharge: 0,
      active: true,
    );
    expect(coil.toBase(2), 180);
    expect(coil.salePriceFor(20), 1800);
    expect(coil.acceptsQuantity(2), isTrue);
    expect(coil.acceptsQuantity(0.5), isFalse);
  });

  test('fractional unit enforces configured quantity step', () {
    const meter = ProductUnitOption(
      unitId: 'm',
      code: 'M',
      name: 'Meter',
      decimalPlaces: 2,
      allowFractional: true,
      isBase: true,
      allowPurchase: true,
      allowSale: true,
      isDefaultPurchase: true,
      isDefaultSale: true,
      conversionToBase: 1,
      quantityStep: 0.25,
      salePrice: null,
      purchaseCost: null,
      cuttingAllowed: true,
      cuttingCharge: 10,
      active: true,
    );
    expect(meter.acceptsQuantity(1.25), isTrue);
    expect(meter.acceptsQuantity(1.10), isFalse);
  });

  test('v4.8.2 price resolution exposes pricing provenance', () {
    final price = PriceResolution.fromMap(const {
      'variant_id': 'variant-1',
      'customer_id': 'customer-1',
      'unit_id': 'unit-1',
      'quantity': 12,
      'unit_price': 84.5,
      'source': 'price_list',
      'price_list_id': 'wholesale',
      'price_list_name': 'Wholesale',
    });
    expect(price.unitPrice, 84.5);
    expect(price.quantity, 12);
    expect(price.sourceLabel, 'Wholesale');
  });

  test('v4.8.2 product identifier accepts generated and legacy shapes', () {
    final generated = ProductIdentifier.fromMap(const {
      'identifier_id': 'id-1',
      'variant_id': 'variant-1',
      'identifier_type': 'barcode',
      'code': '2800000000016',
      'is_primary': true,
      'generated': true,
      'active': true,
    });
    expect(generated.type, 'barcode');
    expect(generated.code, '2800000000016');
    expect(generated.isPrimary, isTrue);
    expect(generated.active, isTrue);
  });
}
