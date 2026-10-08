import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../models/client_session.dart';
import '../models/staff_statement.dart';
import '../services/location_scope_service.dart';
import '../services/operational_export_service.dart';
import '../services/staff_statement_file_builder.dart';
import 'staff_statement_view.dart';

class StaffStatementDialog extends StatefulWidget {
  final ClientSession session;
  final StaffStatement statement;
  const StaffStatementDialog({
    super.key,
    required this.session,
    required this.statement,
  });
  @override
  State<StaffStatementDialog> createState() => _StaffStatementDialogState();
}

class _StaffStatementDialogState extends State<StaffStatementDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _export(String format) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = widget.statement;
      final name =
          'Staff_${s.staffCode}_${s.data['period']['from']}_${s.data['period']['to']}'
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (format == 'json') {
        await OperationalExportService().saveJson(name, s.data);
      } else if (format == 'xlsx') {
        await FileSaver.instance.saveFile(
          name: name,
          bytes: StaffStatementFileBuilder.excel(
            s,
            company: widget.session.business.name,
            location:
                s.data['location_scope']?.toString() ??
                LocationScopeService.scopeLabel(widget.session),
          ),
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final fonts = [
          await rootBundle.load('assets/report_fonts/ReportSans.ttf'),
          await rootBundle.load('assets/report_fonts/ReportSans-Bold.ttf'),
          await rootBundle.load('assets/report_fonts/NotoSansMalayalam.ttf'),
          await rootBundle.load('assets/report_fonts/NotoSansDevanagari.ttf'),
        ];
        final bytes = await StaffStatementFileBuilder.pdf(
          s,
          company: widget.session.business.name,
          location:
              s.data['location_scope']?.toString() ??
              LocationScopeService.scopeLabel(widget.session),
          regular: fonts[0],
          bold: fonts[1],
          fallback: fonts.skip(2).toList(),
        );
        if (format == 'print') {
          await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
        } else {
          await FileSaver.instance.saveFile(
            name: name,
            bytes: bytes,
            fileExtension: 'pdf',
            mimeType: MimeType.pdf,
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Staff statement'),
    content: SizedBox(
      width: 1100,
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: StaffStatementView(statement: widget.statement),
            ),
          ),
        ],
      ),
    ),
    actions: [
      for (final item in {
        'print': 'Print statement / payslips',
        'pdf': 'Save PDF',
        'xlsx': 'Excel statement',
        'json': 'Complete saved data (JSON)',
      }.entries)
        TextButton(
          onPressed: _busy ? null : () => _export(item.key),
          child: Text(item.value),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
