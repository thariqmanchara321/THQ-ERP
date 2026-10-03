import 'package:flutter/material.dart';

class GstPartyMasterController extends ChangeNotifier {
  GstPartyMasterController({
    required String registrationType,
    String? gstin,
    this.initiallyConfigured = false,
  }) : registrationType = _normalizeType(registrationType),
       gstinController = TextEditingController(text: gstin ?? '');

  String registrationType;
  final TextEditingController gstinController;
  final bool initiallyConfigured;

  static const allowedTypes = <String>{
    'registered',
    'unregistered',
    'composition',
    'sez',
    'export',
    'exempt',
  };

  static String _normalizeType(String value) {
    final normalized = value.trim().toLowerCase();
    return allowedTypes.contains(normalized) ? normalized : 'unregistered';
  }

  bool get requiresGstin =>
      registrationType == 'registered' ||
      registrationType == 'composition' ||
      registrationType == 'sez';

  String get gstin => gstinController.text.trim().toUpperCase();

  void setRegistrationType(String value) {
    final normalized = _normalizeType(value);
    if (registrationType == normalized) return;
    registrationType = normalized;
    if (!requiresGstin) {
      gstinController.clear();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    gstinController.dispose();
    super.dispose();
  }
}

class GstPartyMasterFields extends StatelessWidget {
  const GstPartyMasterFields({
    super.key,
    required this.controller,
    required this.enabled,
  });

  final GstPartyMasterController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final statusField = DropdownButtonFormField<String>(
          initialValue: controller.registrationType,
          decoration: const InputDecoration(
            labelText: 'GST Status',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'unregistered',
              child: Text('Unregistered'),
            ),
            DropdownMenuItem(value: 'registered', child: Text('Registered')),
            DropdownMenuItem(value: 'composition', child: Text('Composition')),
            DropdownMenuItem(value: 'sez', child: Text('SEZ')),
            DropdownMenuItem(value: 'export', child: Text('Export')),
            DropdownMenuItem(value: 'exempt', child: Text('Exempt')),
          ],
          onChanged: !enabled
              ? null
              : (value) {
                  if (value != null) controller.setRegistrationType(value);
                },
        );

        final gstinField = TextFormField(
          controller: controller.gstinController,
          enabled: enabled && controller.requiresGstin,
          textCapitalization: TextCapitalization.characters,
          validator: (value) {
            if (controller.requiresGstin &&
                (value == null || value.trim().isEmpty)) {
              return 'GSTIN is required for this GST status.';
            }
            return null;
          },
          decoration: InputDecoration(
            labelText: controller.requiresGstin ? 'GSTIN *' : 'GSTIN',
            hintText: controller.requiresGstin
                ? '15-character GSTIN'
                : 'Not required for this GST status',
            border: const OutlineInputBorder(),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 520) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: statusField),
                      const SizedBox(width: 14),
                      Expanded(child: gstinField),
                    ],
                  );
                }
                return Column(
                  children: [
                    statusField,
                    const SizedBox(height: 14),
                    gstinField,
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(_helperText(), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }

  String _helperText() {
    switch (controller.registrationType) {
      case 'registered':
        return 'GSTIN is validated and the State must match the GSTIN.';
      case 'composition':
        return 'GSTIN is required. Composition status is used by the GST engine.';
      case 'sez':
        return 'GSTIN is required. SEZ supplies remain server-authoritative.';
      case 'export':
        return 'No GSTIN is required. GST Place of Supply is Foreign Country.';
      case 'exempt':
        return 'No GSTIN is required. State is still used for GST context.';
      case 'unregistered':
      default:
        return controller.initiallyConfigured
            ? 'Unregistered GST profile is synchronized with this party.'
            : 'Saving this party creates its normalized Unregistered GST profile.';
    }
  }
}
