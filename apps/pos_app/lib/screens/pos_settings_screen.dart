import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/pos_completion_service.dart';
import '../services/pos_hardware_service.dart';
import '../services/pos_local_backup_service.dart';
import '../services/client_auth_service.dart';
import '../services/device_installation_service.dart';
import '../services/offline_pos_service.dart';
import 'pos_entry_screen.dart';

class PosSettingsScreen extends StatefulWidget {
  final ClientSession session;
  const PosSettingsScreen({super.key, required this.session});

  @override
  State<PosSettingsScreen> createState() => _PosSettingsScreenState();
}

class _PosSettingsScreenState extends State<PosSettingsScreen> {
  final PosCompletionService _service = PosCompletionService();
  final PosHardwareService _hardware = PosHardwareService();
  final PosLocalBackupService _backup = PosLocalBackupService();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _printers = const [];
  List<Map<String, dynamic>> _profiles = const [];
  Map<String, dynamic> _preferences = {};
  String? _invoicePrinter;
  String _paperSize = '80mm';
  bool _autoPrint = false;
  bool _cashDrawer = false;
  String _drawerCommand = 'standard';
  final Set<String> _kotPrinters = {};
  String _backupFolder = '';
  bool _autoBackupOnClose = true;

  String get _tenantId => widget.session.business.id;
  String? get _deviceId => widget.session.device?.deviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      setState(() {
        _error = 'POS device is not activated.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _hardware.listPrinters(),
        _service.printerProfiles(tenantId: _tenantId, deviceId: deviceId),
        _service.getPreferences(tenantId: _tenantId, deviceId: deviceId),
      ]);
      _printers = results[0] as List<String>;
      _profiles = results[1] as List<Map<String, dynamic>>;
      _preferences = results[2] as Map<String, dynamic>;

      Map<String, dynamic>? invoice;
      for (final row in _profiles) {
        if (row['purpose'] == 'invoice' &&
            row['active'] != false &&
            (row['is_default'] == true || invoice == null)) {
          invoice = row;
          if (row['is_default'] == true) break;
        }
      }
      _invoicePrinter = invoice?['printer_name']?.toString();
      if ((_invoicePrinter == null || _invoicePrinter!.isEmpty) &&
          _printers.isNotEmpty) {
        _invoicePrinter = _printers.first;
      }
      _paperSize = invoice?['paper_size']?.toString() ?? '80mm';
      _autoPrint = invoice?['auto_print'] == true;
      _cashDrawer = invoice?['cash_drawer_enabled'] == true;
      _drawerCommand =
          invoice?['cash_drawer_command']?.toString() ?? 'standard';
      _kotPrinters
        ..clear()
        ..addAll(
          _profiles
              .where((row) => row['purpose'] == 'kot' && row['active'] != false)
              .map((row) => row['printer_name']?.toString() ?? '')
              .where((name) => name.isNotEmpty),
        );
      _backupFolder = _preferences['backup_folder']?.toString() ?? '';
      _autoBackupOnClose = _preferences['auto_backup_on_day_close'] != false;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final deviceId = _deviceId;
    final invoicePrinter = _invoicePrinter;
    if (deviceId == null ||
        invoicePrinter == null ||
        invoicePrinter.isEmpty ||
        _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final existingInvoice = _profiles
          .where(
            (row) =>
                row['purpose'] == 'invoice' &&
                row['device_id']?.toString() == deviceId,
          )
          .firstOrNull;
      await _service.savePrinterProfile(
        tenantId: _tenantId,
        deviceId: deviceId,
        profileId: existingInvoice?['id']?.toString(),
        name: 'Invoice • $invoicePrinter',
        purpose: 'invoice',
        paperSize: _paperSize,
        printerName: invoicePrinter,
        autoPrint: _autoPrint,
        cashDrawerEnabled: _cashDrawer,
        cashDrawerCommand: _drawerCommand,
        isDefault: true,
      );

      for (final printer in _printers) {
        final existing = _profiles
            .where(
              (row) =>
                  row['purpose'] == 'kot' &&
                  row['printer_name']?.toString() == printer &&
                  row['device_id']?.toString() == deviceId,
            )
            .firstOrNull;
        if (_kotPrinters.contains(printer) || existing != null) {
          await _service.savePrinterProfile(
            tenantId: _tenantId,
            deviceId: deviceId,
            profileId: existing?['id']?.toString(),
            name: 'KOT • $printer',
            purpose: 'kot',
            paperSize: '80mm',
            printerName: printer,
            routeName: 'Kitchen',
            autoPrint: _kotPrinters.contains(printer),
            active: _kotPrinters.contains(printer),
          );
        }
      }

      final nextPreferences = Map<String, dynamic>.from(_preferences)
        ..['backup_folder'] = _backupFolder
        ..['auto_backup_on_day_close'] = _autoBackupOnClose
        ..['invoice_printer'] = invoicePrinter
        ..['paper_size'] = _paperSize;
      await _service.setPreferences(
        tenantId: _tenantId,
        deviceId: deviceId,
        settings: nextPreferences,
      );
      _preferences = nextPreferences;
      await _load();
      _message('POS hardware settings saved.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final path = await _backup.chooseBackupFolder();
      if (path != null && mounted) setState(() => _backupFolder = path);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _backupNow() async {
    try {
      final path = await _backup.backupNow(
        tenantId: _tenantId,
        businessName: widget.session.business.name,
        deviceCode: widget.session.device?.deviceCode ?? 'POS',
        folderPath: _backupFolder,
      );
      _message('Local backup created: $path');
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _testPrint() async {
    final printer = _invoicePrinter;
    if (printer == null || printer.isEmpty) return;
    try {
      await _hardware.testPrint(printer, paperSize: _paperSize);
      _message('Test print sent to $printer.');
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _testDrawer() async {
    final printer = _invoicePrinter;
    if (printer == null || printer.isEmpty) return;
    try {
      await _hardware.openCashDrawer(
        printerName: printer,
        command: _drawerCommand,
      );
      _message('Cash drawer pulse sent.');
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changeStoreBusiness() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('POS device is not activated.');
      return;
    }

    try {
      final summary = await OfflinePosService.instance.summary(
        tenantId: _tenantId,
        deviceId: deviceId,
      );
      if (summary.needsAttention > 0) {
        _message(
          'Cannot reset this POS while offline invoices need attention. '
          'Sync/resolve ${summary.needsAttention} pending, conflict or error invoice(s) first.',
        );
        return;
      }
    } catch (error) {
      _message(
        'Could not verify the offline queue, so THQ will not reset this POS. $error',
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Store / Business?'),
        content: const Text(
          'This signs out and clears the current business/device activation. '
          'The permanent installation ID is kept. You will return to Business '
          'Code + POS Activation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset & Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ClientAuthService().signOut();
      await DeviceInstallationService().clearActivation();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PosEntryScreen()),
        (_) => false,
      );
    } catch (error) {
      _message('POS reset failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return ListView(
          padding: EdgeInsets.all(compact ? 12 : 18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POS Settings',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Receipt printer, KOT routing, cash drawer and local backups.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  tooltip: 'Rescan printers',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _section(
              title: 'Invoice / receipt printer',
              icon: Icons.print_outlined,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _printers.contains(_invoicePrinter)
                        ? _invoicePrinter
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Printer'),
                    items: _printers
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _invoicePrinter = value),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _paperSize,
                          decoration: const InputDecoration(labelText: 'Paper'),
                          items: const [
                            DropdownMenuItem(
                              value: '58mm',
                              child: Text('58mm Thermal'),
                            ),
                            DropdownMenuItem(
                              value: '80mm',
                              child: Text('80mm Thermal'),
                            ),
                            DropdownMenuItem(value: 'a4', child: Text('A4')),
                          ],
                          onChanged: (v) =>
                              setState(() => _paperSize = v ?? '80mm'),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Auto print invoice'),
                        selected: _autoPrint,
                        onSelected: (v) => setState(() => _autoPrint = v),
                      ),
                      FilterChip(
                        label: const Text('Cash drawer'),
                        selected: _cashDrawer,
                        onSelected: (v) => setState(() => _cashDrawer = v),
                      ),
                    ],
                  ),
                  if (_cashDrawer) ...[
                    const SizedBox(height: 9),
                    DropdownButtonFormField<String>(
                      initialValue:
                          const ['standard', 'drawer2'].contains(_drawerCommand)
                          ? _drawerCommand
                          : 'standard',
                      decoration: const InputDecoration(
                        labelText: 'Cash drawer pulse',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('ESC/POS Drawer 1 / Pin 2'),
                        ),
                        DropdownMenuItem(
                          value: 'drawer2',
                          child: Text('ESC/POS Drawer 2 / Pin 5'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _drawerCommand = v ?? 'standard'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _invoicePrinter == null ? null : _testPrint,
                        icon: const Icon(Icons.print),
                        label: const Text('Test Print'),
                      ),
                      OutlinedButton.icon(
                        onPressed: !_cashDrawer || _invoicePrinter == null
                            ? null
                            : _testDrawer,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Test Drawer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _section(
              title: 'Kitchen / KOT printers',
              icon: Icons.soup_kitchen_outlined,
              child: _printers.isEmpty
                  ? const Text('No printers detected.')
                  : Column(
                      children: _printers
                          .map(
                            (name) => CheckboxListTile(
                              value: _kotPrinters.contains(name),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _kotPrinters.add(name);
                                } else {
                                  _kotPrinters.remove(name);
                                }
                              }),
                              title: Text(name),
                              subtitle: const Text(
                                'Selected printers receive KOT tickets. Multiple printers are supported.',
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 10),
            _section(
              title: 'Local backup',
              icon: Icons.backup_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _backupFolder.isEmpty
                        ? 'No backup folder selected.'
                        : _backupFolder,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _chooseFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Choose Folder'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _backupFolder.isEmpty ? null : _backupNow,
                        icon: const Icon(Icons.backup),
                        label: const Text('Backup Now'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    value: _autoBackupOnClose,
                    onChanged: (v) => setState(() => _autoBackupOnClose = v),
                    title: const Text('Backup automatically after Shift Close'),
                    subtitle: const Text(
                      'After a successful Cashier Shift close, THQ writes a complete business JSON backup to this folder when enabled.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _section(
              title: 'Store / business activation',
              icon: Icons.restart_alt,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use this only when this POS must be activated for a different store or business.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _changeStoreBusiness,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Change Store / Business'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving || _invoicePrinter == null ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save POS Settings'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
