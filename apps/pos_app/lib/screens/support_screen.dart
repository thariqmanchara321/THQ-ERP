import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/software_update_service.dart';
import '../services/support_service.dart';

class SupportScreen extends StatefulWidget {
  final ClientSession session;
  final String appKey;

  const SupportScreen({super.key, required this.session, this.appKey = 'pos'});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final SupportService _service = SupportService();
  final SoftwareUpdateService _updateService = SoftwareUpdateService();
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String _category = 'general';
  String _priority = 'normal';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _updateService.initialize(
      tenantId: widget.session.business.id,
      deviceId: widget.session.device?.deviceId,
    );
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Subject and description are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _service.createTicket(
        tenantId: widget.session.business.id,
        locationId: widget.session.device?.locationId,
        deviceId: widget.session.device?.deviceId,
        appKey: widget.appKey,
        appVersion: ThqReleaseContract.appVersion,
        category: _category,
        priority: _priority,
        subject: _subject.text,
        description: _description.text,
      );
      if (!mounted) return;
      final number = result['ticket_number']?.toString() ?? 'Support ticket';
      _subject.clear();
      _description.clear();
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('$number created.')),
      );
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndInstall() async {
    final tenantId = widget.session.business.id;
    final deviceId = widget.session.device?.deviceId ?? '';

    // Check unsynced transactions in POS offline queue
    final unsynced = await _updateService.checkUnsyncedInvoices(
      tenantId: tenantId,
      deviceId: deviceId,
    );

    if (!mounted) return;

    if (unsynced > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
          title: const Text('Sync Required Before Updating'),
          content: Text(
            'There are $unsynced unsynced offline transactions in the local queue.\n\n'
            'To protect business records and accounting truth, updating is blocked until all transactions are safely synchronized.\n\n'
            'Please synchronize your offline transactions before proceeding.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final readiness = ErpUpdateReadinessService();
    if (!readiness.isSafeToUpdate) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline, color: Colors.amber, size: 36),
          title: const Text('Update Paused: Operation in Progress'),
          content: Text(
            'An operation is in progress (${readiness.summaryBlockReason}).\n\n'
            'The update will be available when your work is safely completed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Install Later'),
            ),
            OutlinedButton(
              onPressed: () {
                readiness.scheduleInstallOnClose(true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Update will install automatically when THQ POS is closed.'),
                  ),
                );
              },
              child: const Text('Install on Next Application Close'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Software Update'),
        content: const Text(
          'THQ POS will close safely and the installer will upgrade your application.\n\n'
          'All store activations, device configurations and offline databases will remain preserved.\n\n'
          'Proceed with installation now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Install Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Install Now'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _updateService.installUpdate(
      tenantId: tenantId,
      deviceId: deviceId,
      silent: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Support Centre',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Business, store, device and user context attach automatically',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    children: [
                      ValueListenableBuilder<SoftwareUpdateState>(
                        valueListenable: _updateService.stateNotifier,
                        builder: (context, updateState, _) {
                          return _buildSoftwareUpdatesPanel(context, updateState);
                        },
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Submit Support Request',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                _contextChip(
                                  Icons.business_outlined,
                                  widget.session.business.name,
                                ),
                                _contextChip(
                                  Icons.store_outlined,
                                  widget.session.device?.locationCode ??
                                      'No device',
                                ),
                                _contextChip(
                                  Icons.computer_outlined,
                                  widget.session.device?.deviceCode ??
                                      widget.appKey,
                                ),
                                _contextChip(
                                  Icons.person_outline,
                                  widget.session.username,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _subject,
                              decoration: const InputDecoration(
                                labelText: 'Subject',
                                prefixIcon: Icon(Icons.subject, size: 17),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _category,
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'general',
                                        child: Text('General'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'billing',
                                        child: Text('Billing'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'inventory',
                                        child: Text('Inventory'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'printing',
                                        child: Text('Printing'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'login',
                                        child: Text('Login / Access'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'error',
                                        child: Text('Error / Crash'),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _category = v ?? 'general'),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _priority,
                                    decoration: const InputDecoration(
                                      labelText: 'Priority',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'low',
                                        child: Text('Low'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'normal',
                                        child: Text('Normal'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'high',
                                        child: Text('High'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'urgent',
                                        child: Text('Urgent'),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _priority = v ?? 'normal'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: _description,
                              minLines: 4,
                              maxLines: 8,
                              decoration: const InputDecoration(
                                labelText: 'Describe what happened',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _submit,
                                icon: const Icon(Icons.send_outlined, size: 15),
                                label: Text(
                                  _saving ? 'Sending...' : 'Send Support Request',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftwareUpdatesPanel(BuildContext context, SoftwareUpdateState updateState) {
    final scheme = Theme.of(context).colorScheme;
    final rel = updateState.release;
    final isBusy = updateState.status.isBusy;

    Color badgeBg;
    Color badgeFg;
    String badgeText;

    switch (updateState.status) {
      case UpdateStatus.checking:
        badgeBg = scheme.primaryContainer;
        badgeFg = scheme.onPrimaryContainer;
        badgeText = 'Checking…';
        break;
      case UpdateStatus.available:
        badgeBg = Colors.teal.shade100;
        badgeFg = Colors.teal.shade900;
        badgeText = 'Update Available';
        break;
      case UpdateStatus.downloading:
        badgeBg = Colors.blue.shade100;
        badgeFg = Colors.blue.shade900;
        badgeText = 'Downloading';
        break;
      case UpdateStatus.paused:
        badgeBg = Colors.orange.shade100;
        badgeFg = Colors.orange.shade900;
        badgeText = 'Download Paused';
        break;
      case UpdateStatus.downloaded:
      case UpdateStatus.readyToInstall:
        badgeBg = Colors.green.shade100;
        badgeFg = Colors.green.shade900;
        badgeText = 'Ready to Install';
        break;
      case UpdateStatus.verifying:
      case UpdateStatus.verifyingNewVersion:
        badgeBg = Colors.indigo.shade100;
        badgeFg = Colors.indigo.shade900;
        badgeText = 'Verifying Integrity';
        break;
      case UpdateStatus.waitingForSafeShutdown:
        badgeBg = Colors.amber.shade100;
        badgeFg = Colors.amber.shade900;
        badgeText = 'Preparing Shutdown…';
        break;
      case UpdateStatus.installing:
        badgeBg = Colors.amber.shade100;
        badgeFg = Colors.amber.shade900;
        badgeText = 'Installing…';
        break;
      case UpdateStatus.restarting:
        badgeBg = Colors.amber.shade100;
        badgeFg = Colors.amber.shade900;
        badgeText = 'Restarting App…';
             case UpdateStatus.succeeded:
        badgeBg = Colors.green.shade100;
        badgeFg = Colors.green.shade900;
        badgeText = 'Update Succeeded';
        break;
      case UpdateStatus.failed:
        badgeBg = scheme.errorContainer;
        badgeFg = scheme.onErrorContainer;
        badgeText = 'Update Failed';
        break;
      case UpdateStatus.recovered:
        badgeBg = Colors.purple.shade100;
        badgeFg = Colors.purple.shade900;
        badgeText = 'Preserved (Rollback)';
        break;
      case UpdateStatus.error:
        badgeBg = scheme.errorContainer;
        badgeFg = scheme.onErrorContainer;
        badgeText = 'Update Error';
        break;
      case UpdateStatus.upToDate:
      case UpdateStatus.idle:
        if (rel != null && rel.isUpdateAvailable) {
          badgeBg = Colors.teal.shade100;
          badgeFg = Colors.teal.shade900;
          badgeText = 'Update Available';
        } else {
          badgeBg = scheme.surfaceContainerHighest;
          badgeFg = scheme.onSurfaceVariant;
          badgeText = 'Up to Date';
        }
        break;
    }

    String formatDateTime(DateTime? dt) {
      if (dt == null) return 'Never';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: scheme.primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Software Updates',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _infoRow(
                  context,
                  label: 'Installed Version',
                  value: updateState.installedVersionDisplay,
                ),
                const Divider(height: 8),
                _infoRow(
                  context,
                  label: 'Latest Eligible Version',
                  value: (rel != null && rel.latestVersion.isNotEmpty && rel.isUpdateAvailable)
                      ? 'v${rel.latestVersion} (Build ${rel.latestBuild})'
                      : (updateState.failedTargetVersion != null
                          ? 'v${updateState.failedTargetVersion} (Build ${updateState.failedTargetBuild})'
                          : updateState.latestEligibleVersionDisplay),
                ),
                if (updateState.pendingUpdateDisplay != null) ...[
                  const Divider(height: 8),
                  _infoRow(
                    context,
                    label: 'Pending Update',
                    value: updateState.pendingUpdateDisplay!,
                    valueColor: Colors.green.shade700,
                  ),
                ],
                if (updateState.hasFailedAttempt) ...[
                  const Divider(height: 8),
                  _infoRow(
                    context,
                    label: 'Last Update Attempt',
                    value: 'Failed (v${updateState.failedTargetVersion} b${updateState.failedTargetBuild})',
                    valueColor: scheme.error,
                  ),
                ] else if (updateState.lastSuccessfulUpdate != null) ...[
                  const Divider(height: 8),
                  _infoRow(
                    context,
                    label: 'Last Update Attempt',
                    value: 'Success at ${formatDateTime(updateState.lastSuccessfulUpdate)}',
                    valueColor: Colors.green.shade700,
                  ),
                ],
                const Divider(height: 8),
                _infoRow(
                  context,
                  label: 'Last Checked',
                  value: formatDateTime(updateState.lastCheckedAt),
                ),
                if (rel != null && rel.packageSizeBytes > 0) ...[
                  const Divider(height: 8),
                  _infoRow(
                    context,
                    label: 'Download Package Size',
                    value: rel.formattedSize,
                  ),
                ],
              ],
            ),
          ),
          if (updateState.hasFailedAttempt) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: scheme.error, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Failed Update: v${updateState.failedTargetVersion} (Build ${updateState.failedTargetBuild})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${updateState.lastAttemptReason ?? "Installation could not complete. Original application was preserved safely."}',
                    style: TextStyle(fontSize: 11, color: scheme.onErrorContainer),
                  ),
                  if (updateState.lastAttemptTimestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Attempted: ${formatDateTime(updateState.lastAttemptTimestamp)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onErrorContainer.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (updateState.errorMessage != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      updateState.errorMessage!,
                      style: TextStyle(fontSize: 11, color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rel != null && rel.releaseNotes.isNotEmpty && rel.isUpdateAvailable) ...[
            const SizedBox(height: 8),
            const Text(
              'Release Notes:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rel.releaseNotes,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          if (updateState.status == UpdateStatus.downloading &&
              updateState.downloadProgress != null) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      updateState.downloadProgress!.statusText,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      updateState.downloadProgress!.percentageText,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: updateState.downloadProgress!.progressFraction > 0
                      ? updateState.downloadProgress!.progressFraction
                      : null,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    updateState.downloadProgress!.downloadedFormatted,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () => _updateService.checkForUpdate(
                          tenantId: widget.session.business.id,
                          deviceId: widget.session.device?.deviceId,
                          locationId: widget.session.device?.locationId,
                        ),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Check for Updates'),
              ),
              if (updateState.status == UpdateStatus.available && !updateState.status.canInstall)
                FilledButton.icon(
                  onPressed: () => _updateService.downloadRelease(
                    tenantId: widget.session.business.id,
                    deviceId: widget.session.device?.deviceId,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download Update'),
                ),
              if (updateState.status == UpdateStatus.downloading)
                OutlinedButton.icon(
                  onPressed: _updateService.cancelDownload,
                  icon: const Icon(Icons.cancel_outlined, size: 14),
                  label: const Text('Cancel Download'),
                ),
              if (updateState.status.canInstall)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _confirmAndInstall,
                  icon: const Icon(Icons.system_update_rounded, size: 14),
                  label: const Text('Update & Restart'),
                ),
              if (updateState.hasFailedAttempt ||
                  updateState.status == UpdateStatus.failed ||
                  updateState.status == UpdateStatus.error) ...[
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _updateService.retryUpdate(
                            tenantId: widget.session.business.id,
                            deviceId: widget.session.device?.deviceId,
                            locationId: widget.session.device?.locationId,
                          ),
                  icon: const Icon(Icons.replay_rounded, size: 14),
                  label: const Text('Retry Update'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showErrorDetailsModal(context, updateState),
                  icon: const Icon(Icons.bug_report_outlined, size: 14),
                  label: const Text('View Error Details'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyDiagnosticReport(context),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy Diagnostic Report'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showErrorDetailsModal(BuildContext context, SoftwareUpdateState updateState) {
    showThqDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Update Diagnostic Details'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  updateState.lastAttemptReason ??
                      'The update installer exited before completing setup.',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Safety State',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Running version remains intact at v${ThqReleaseContract.appVersion} (Build ${ThqReleaseContract.buildNumber}). No user settings, databases, or local data were altered.',
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Technical Details (For Administrators & Support)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    'Target Version: ${updateState.failedTargetVersion ?? "Unknown"}\n'
                    'Target Build: ${updateState.failedTargetBuild ?? 0}\n'
                    'Exit Code: ${updateState.lastAttemptExitCode ?? "None"}\n'
                    'Session Status: ${updateState.lastAttemptStatus ?? "None"}\n'
                    'Attempt ID: ${updateState.lastAttemptId ?? "None"}\n'
                    'Timestamp: ${updateState.lastAttemptTimestamp?.toIso8601String() ?? "None"}\n'
                    'Raw Error: ${updateState.lastAttemptRawError ?? updateState.errorMessage ?? "None"}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              final report = _updateService.generateDiagnosticReport(
                tenantId: widget.session.business.id,
                deviceId: widget.session.device?.deviceId,
              );
              Clipboard.setData(ClipboardData(text: report));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostic report copied to clipboard.')),
              );
            },
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy Report'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _copyDiagnosticReport(BuildContext context) {
    final report = _updateService.generateDiagnosticReport(
      tenantId: widget.session.business.id,
      deviceId: widget.session.device?.deviceId,
    );
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied to clipboard.')),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _contextChip(IconData icon, String value) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(value.isEmpty ? 'Unknown' : value),
  );
}

