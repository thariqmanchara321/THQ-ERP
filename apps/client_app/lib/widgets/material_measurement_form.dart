import 'package:flutter/material.dart';
import '../models/material_measurement_engine.dart';

/// A compact, rich, futuristic measurement card/form adhering to Material Yard V2 specs.
class MaterialMeasurementForm extends StatefulWidget {
  final MaterialMeasurementData initialData;
  final ValueChanged<MaterialMeasurementData> onChanged;

  const MaterialMeasurementForm({
    super.key,
    required this.initialData,
    required this.onChanged,
  });

  @override
  State<MaterialMeasurementForm> createState() =>
      _MaterialMeasurementFormState();
}

class _MaterialMeasurementFormState extends State<MaterialMeasurementForm> {
  late MaterialMeasurementData _data;

  late TextEditingController _manualQtyCtrl;
  late TextEditingController _lenCtrl;
  late TextEditingController _lenInCtrl;
  late TextEditingController _widCtrl;
  late TextEditingController _widInCtrl;
  late TextEditingController _hgtCtrl;
  late TextEditingController _hgtInCtrl;

  late TextEditingController _grossCtrl;
  late TextEditingController _tareCtrl;
  late TextEditingController _densityCtrl;

  late TextEditingController _heapAdjCtrl;
  late TextEditingController _billableQtyCtrl;
  late TextEditingController _varianceReasonCtrl;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;

    _manualQtyCtrl = TextEditingController(
      text: _data.physicalQty > 0 ? _data.physicalQty.toString() : '',
    );
    _lenCtrl = TextEditingController(
      text: _data.length != null ? _data.length.toString() : '',
    );
    _lenInCtrl = TextEditingController(
      text: _data.lengthIn != null ? _data.lengthIn.toString() : '',
    );
    _widCtrl = TextEditingController(
      text: _data.width != null ? _data.width.toString() : '',
    );
    _widInCtrl = TextEditingController(
      text: _data.widthIn != null ? _data.widthIn.toString() : '',
    );
    _hgtCtrl = TextEditingController(
      text: _data.height != null ? _data.height.toString() : '',
    );
    _hgtInCtrl = TextEditingController(
      text: _data.heightIn != null ? _data.heightIn.toString() : '',
    );

    _grossCtrl = TextEditingController(
      text: _data.grossWeight != null ? _data.grossWeight.toString() : '',
    );
    _tareCtrl = TextEditingController(
      text: _data.tareWeight != null ? _data.tareWeight.toString() : '',
    );
    _densityCtrl = TextEditingController(
      text: _data.bulkDensity != null ? _data.bulkDensity.toString() : '',
    );

    _heapAdjCtrl = TextEditingController(
      text: _data.heapAdjustmentCft != 0
          ? _data.heapAdjustmentCft.toString()
          : '',
    );
    _billableQtyCtrl = TextEditingController(
      text: _data.approvedBillableQty > 0
          ? _data.approvedBillableQty.toString()
          : '',
    );
    _varianceReasonCtrl = TextEditingController(
      text: _data.varianceReason ?? '',
    );

    _recalculate(notifyParent: false);
  }

  @override
  void dispose() {
    _manualQtyCtrl.dispose();
    _lenCtrl.dispose();
    _lenInCtrl.dispose();
    _widCtrl.dispose();
    _widInCtrl.dispose();
    _hgtCtrl.dispose();
    _hgtInCtrl.dispose();
    _grossCtrl.dispose();
    _tareCtrl.dispose();
    _densityCtrl.dispose();
    _heapAdjCtrl.dispose();
    _billableQtyCtrl.dispose();
    _varianceReasonCtrl.dispose();
    super.dispose();
  }

  double _parse(String text) => double.tryParse(text.trim()) ?? 0.0;

  void _onDimensionUnitChanged(String newUnitCode) {
    final oldUnit = DimensionUnit.fromCode(_data.dimensionUnit);
    final newUnit = DimensionUnit.fromCode(newUnitCode);
    if (oldUnit == newUnit) return;

    final l = _parse(_lenCtrl.text);
    final lIn = _parse(_lenInCtrl.text);
    final w = _parse(_widCtrl.text);
    final wIn = _parse(_widInCtrl.text);
    final h = _parse(_hgtCtrl.text);
    final hIn = _parse(_hgtInCtrl.text);

    if (l > 0 || w > 0 || h > 0) {
      final (newL, newLIn) = MaterialMeasurementEngine.convertDimension(
        mainValue: l,
        inchesPart: lIn,
        from: oldUnit,
        to: newUnit,
      );
      final (newW, newWIn) = MaterialMeasurementEngine.convertDimension(
        mainValue: w,
        inchesPart: wIn,
        from: oldUnit,
        to: newUnit,
      );
      final (newH, newHIn) = MaterialMeasurementEngine.convertDimension(
        mainValue: h,
        inchesPart: hIn,
        from: oldUnit,
        to: newUnit,
      );

      _lenCtrl.text = newL > 0 ? (newL % 1 == 0 ? newL.toInt().toString() : newL.toString()) : '';
      _lenInCtrl.text = newLIn > 0 ? (newLIn % 1 == 0 ? newLIn.toInt().toString() : newLIn.toString()) : '';
      _widCtrl.text = newW > 0 ? (newW % 1 == 0 ? newW.toInt().toString() : newW.toString()) : '';
      _widInCtrl.text = newWIn > 0 ? (newWIn % 1 == 0 ? newWIn.toInt().toString() : newWIn.toString()) : '';
      _hgtCtrl.text = newH > 0 ? (newH % 1 == 0 ? newH.toInt().toString() : newH.toString()) : '';
      _hgtInCtrl.text = newHIn > 0 ? (newHIn % 1 == 0 ? newHIn.toInt().toString() : newHIn.toString()) : '';
    }

    setState(() {
      _data.dimensionUnit = newUnitCode;
      _recalculate();
    });
  }

  void _recalculate({bool notifyParent = true}) {
    double calcCft = 0.0;

    if (_data.method == 'dimensions') {
      final l = _parse(_lenCtrl.text);
      final lIn = _parse(_lenInCtrl.text);
      final w = _parse(_widCtrl.text);
      final wIn = _widInCtrl.text.isNotEmpty ? _parse(_widInCtrl.text) : 0.0;
      final h = _parse(_hgtCtrl.text);
      final hIn = _hgtInCtrl.text.isNotEmpty ? _parse(_hgtInCtrl.text) : 0.0;

      _data.length = l;
      _data.lengthIn = lIn;
      _data.width = w;
      _data.widthIn = wIn;
      _data.height = h;
      _data.heightIn = hIn;

      switch (_data.dimensionUnit) {
        case 'in':
          calcCft = MaterialMeasurementEngine.calculateFromInches(
            lengthIn: l,
            widthIn: w,
            heightIn: h,
          );
          break;
        case 'ft_in':
          calcCft = MaterialMeasurementEngine.calculateFromFeetAndInches(
            lengthFt: l,
            lengthIn: lIn,
            widthFt: w,
            widthIn: wIn,
            heightFt: h,
            heightIn: hIn,
          );
          break;
        case 'm':
          calcCft = MaterialMeasurementEngine.calculateFromMetres(
            lengthM: l,
            widthM: w,
            heightM: h,
          );
          break;
        case 'cm':
          calcCft = MaterialMeasurementEngine.calculateFromCentimetres(
            lengthCm: l,
            widthCm: w,
            heightCm: h,
          );
          break;
        case 'ft':
        default:
          calcCft = MaterialMeasurementEngine.calculateFromFeet(
            lengthFt: l,
            widthFt: w,
            heightFt: h,
          );
          break;
      }

      final heapAdj = _parse(_heapAdjCtrl.text);
      _data.heapAdjustmentCft = heapAdj;
      _data.calculatedCft = calcCft;
      final netPhys = (calcCft + heapAdj);
      _data.physicalQty = netPhys > 0 ? netPhys : 0.0;
      _data.unitCode = 'CFT';
    } else if (_data.method == 'weighbridge') {
      final gross = _parse(_grossCtrl.text);
      final tare = _parse(_tareCtrl.text);
      final density = _parse(_densityCtrl.text);

      _data.grossWeight = gross;
      _data.tareWeight = tare;
      _data.bulkDensity = density > 0 ? density : null;

      final netWeight = MaterialMeasurementEngine.calculateNetWeight(
        grossWeight: gross,
        tareWeight: tare,
      );

      if (_data.isDensityApproved && density > 0) {
        final cft = MaterialMeasurementEngine.convertWeightToCft(
          netWeight: netWeight,
          bulkDensity: density,
          isDensityApproved: true,
        );
        calcCft = cft ?? 0.0;
        _data.calculatedCft = calcCft;
        _data.physicalQty = calcCft;
        _data.unitCode = 'CFT';
      } else {
        _data.calculatedCft = 0.0;
        _data.physicalQty = netWeight;
        _data.unitCode = 'TON';
      }
    } else {
      // manual
      final manualQty = _parse(_manualQtyCtrl.text);
      _data.physicalQty = manualQty;
      _data.calculatedCft = _data.unitCode == 'CFT' ? manualQty : 0.0;
    }

    // Default approved billable quantity to physical quantity if blank
    if (_billableQtyCtrl.text.trim().isEmpty) {
      _data.approvedBillableQty = _data.physicalQty;
    } else {
      _data.approvedBillableQty = _parse(_billableQtyCtrl.text);
    }

    _data.varianceReason = _varianceReasonCtrl.text.trim();

    if (notifyParent) {
      widget.onChanged(_data);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasVariance =
        (_data.approvedBillableQty - _data.physicalQty).abs() > 0.001 &&
        _data.physicalQty > 0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.straighten, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Measurement & Quantity Engine',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'manual', label: Text('Manual')),
                  ButtonSegment(
                    value: 'dimensions',
                    label: Text('Body Dimensions'),
                  ),
                  ButtonSegment(
                    value: 'weighbridge',
                    label: Text('Weighbridge'),
                  ),
                ],
                selected: {_data.method},
                onSelectionChanged: (set) {
                  setState(() {
                    _data.method = set.first;
                    _recalculate();
                  });
                },
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // METHOD 1: MANUAL
          if (_data.method == 'manual') ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _manualQtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.numbers, size: 18),
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _data.unitCode,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CFT', child: Text('CFT')),
                      DropdownMenuItem(value: 'TON', child: Text('TON')),
                      DropdownMenuItem(value: 'CBM', child: Text('CBM')),
                      DropdownMenuItem(value: 'LOAD', child: Text('LOAD')),
                      DropdownMenuItem(value: 'BRASS', child: Text('BRASS')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _data.unitCode = val ?? 'CFT';
                        _recalculate();
                      });
                    },
                  ),
                ),
              ],
            ),
          ],

          // METHOD 2: DIMENSIONS
          if (_data.method == 'dimensions') ...[
            Row(
              children: [
                Text(
                  'Dimension Unit:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _data.dimensionUnit,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ft', child: Text('Feet (ft)')),
                    DropdownMenuItem(value: 'in', child: Text('Inches (in)')),
                    DropdownMenuItem(
                      value: 'ft_in',
                      child: Text('Feet & Inches (ft + in)'),
                    ),
                    DropdownMenuItem(value: 'm', child: Text('Metres (m)')),
                    DropdownMenuItem(
                      value: 'cm',
                      child: Text('Centimetres (cm)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) _onDimensionUnitChanged(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_data.dimensionUnit == 'ft_in') ...[
              // Feet and Inches Inputs
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Length ft',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _lenInCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Length in',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _widCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Width ft',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _widInCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Width in',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _hgtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Height ft',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _hgtInCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Height in',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Standard single-unit dimension inputs
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Length (${_data.dimensionUnit})',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _widCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Width (${_data.dimensionUnit})',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hgtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Height (${_data.dimensionUnit})',
                        isDense: true,
                      ),
                      onChanged: (_) => _recalculate(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heapAdjCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Heap Adjustment (CFT)',
                      hintText: 'e.g. +12 or -5',
                      prefixIcon: Icon(Icons.terrain, size: 16),
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Body: ${MaterialMeasurementEngine.formatCft(_data.calculatedCft)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'Total: ${MaterialMeasurementEngine.formatCft(_data.physicalQty)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          // METHOD 3: WEIGHBRIDGE
          if (_data.method == 'weighbridge') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grossCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Gross Weight (Ton/Kg)',
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tareCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tare Weight (Ton/Kg)',
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Net Weight', style: theme.textTheme.labelSmall),
                        Text(
                          '${MaterialMeasurementEngine.calculateNetWeight(grossWeight: _parse(_grossCtrl.text), tareWeight: _parse(_tareCtrl.text)).toStringAsFixed(3)} Ton',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _densityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Bulk Density (Ton/CFT)',
                      hintText: 'e.g. 0.045',
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Approved Density Conversion'),
                    subtitle: const Text('Required to convert Weight to CFT'),
                    value: _data.isDensityApproved,
                    onChanged: (val) {
                      setState(() {
                        _data.isDensityApproved = val ?? false;
                        _recalculate();
                      });
                    },
                  ),
                ),
              ],
            ),
          ],

          const Divider(height: 24),

          // AUDITED BILLABLE QUANTITY & VARIANCE
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Physical Quantity:',
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      MaterialMeasurementEngine.formatQuantity(_data.physicalQty, _data.unitCode),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _billableQtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Approved Billable Qty (${_data.unitCode})',
                    helperText: 'Defaults to physical quantity',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalculate(),
                ),
              ),
            ],
          ),

          if (hasVariance) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: scheme.error),
                      const SizedBox(width: 6),
                      Text(
                        'Variance Detected: ${MaterialMeasurementEngine.formatQuantity((_data.approvedBillableQty - _data.physicalQty).abs(), _data.unitCode)}',
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _varianceReasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Authorized Variance Reason',
                      hintText: 'e.g. Moisture deduction, customer agreed discount, stone settling',
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculate(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
