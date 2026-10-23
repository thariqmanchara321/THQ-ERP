import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import '../services/system_health_service.dart';

class SystemHealthPanel extends StatefulWidget {
  final SystemHealthService? healthService;
  final String? tenantId;
  final String? deviceId;
  final bool autoRun;

  const SystemHealthPanel({
    super.key,
    this.healthService,
    this.tenantId,
    this.deviceId,
    this.autoRun = true,
  });

  @override
  State<SystemHealthPanel> createState() => _SystemHealthPanelState();
}

class _SystemHealthPanelState extends State<SystemHealthPanel> {
  late final SystemHealthService _service;
  SystemHealthReport? _report;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _service = widget.healthService ?? SystemHealthService();
    if (widget.autoRun) {
      _runCheck();
    }
  }

  Future<void> _runCheck() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final res = await _service.runSystemCheck(
        tenantId: widget.tenantId,
        deviceId: widget.deviceId,
      );
      if (mounted) {
        setState(() {
          _report = res;
          _isChecking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'None recorded';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final report = _report;
    final dbStatus = _isChecking
        ? DatabaseConnectionStatus.checking
        : (report?.databaseStatus ?? DatabaseConnectionStatus.checking);

    Color dbColor;
    String dbText;
    switch (dbStatus) {
      case DatabaseConnectionStatus.checking:
        dbColor = Colors.amber;
        dbText = 'Checking…';
        break;
      case DatabaseConnectionStatus.connected:
        dbColor = isDark ? Colors.tealAccent.shade400 : Colors.teal.shade700;
        dbText = report?.databaseLatencyMs != null
            ? 'Connected (${report!.databaseLatencyMs} ms)'
            : 'Connected';
        break;
      case DatabaseConnectionStatus.disconnected:
        dbColor = scheme.error;
        dbText = 'Disconnected';
        break;
    }

    final accentTeal = isDark ? const Color(0xFF00E5FF) : const Color(0xFF00796B);
    final bannerBg = isDark
        ? const Color(0xFF09292E)
        : const Color(0xFFE0F7FA);
    final bannerBorder = isDark
        ? const Color(0xFF00E5FF).withValues(alpha: 0.35)
        : const Color(0xFF00796B).withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3A45) : scheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, size: 18, color: accentTeal),
              const SizedBox(width: 8),
              Text(
                'SYSTEM HEALTH & VERIFICATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFFB2EBF2) : const Color(0xFF004D40),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(
                      color: accentTeal.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _isChecking ? null : _runCheck,
                  icon: _isChecking
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(accentTeal),
                          ),
                        )
                      : Icon(Icons.refresh_rounded, size: 14, color: accentTeal),
                  label: Text(
                    'Run System Check',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accentTeal,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Verification Indicator Banner (Compiled into Flutter)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bannerBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: bannerBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: accentTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report?.updateVerificationMessage ??
                        'THQ Update Test #2 — New Feature Installed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFE0F7FA) : const Color(0xFF004D40),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Metric Rows
          _metricRow(
            context,
            label: 'Application Status',
            value: report?.applicationStatusDisplay ?? 'Running (Operational)',
            valueColor: isDark ? Colors.tealAccent.shade400 : Colors.teal.shade800,
            icon: Icons.check_circle_outline,
            iconColor: isDark ? Colors.tealAccent.shade400 : Colors.teal.shade800,
          ),
          const Divider(height: 10),
          _metricRow(
            context,
            label: 'Database Connection',
            value: dbText,
            valueColor: dbColor,
            icon: dbStatus == DatabaseConnectionStatus.connected
                ? Icons.link_rounded
                : (dbStatus == DatabaseConnectionStatus.checking
                    ? Icons.sync_rounded
                    : Icons.link_off_rounded),
            iconColor: dbColor,
          ),
          if (report?.databaseErrorMessage != null &&
              dbStatus == DatabaseConnectionStatus.disconnected) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Check failed: ${report!.databaseErrorMessage}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const Divider(height: 10),
          _metricRow(
            context,
            label: 'Current Version and Build',
            value: report?.versionBuildDisplay ??
                'v${ThqReleaseContract.appVersion} (Build ${ThqReleaseContract.buildNumber})',
            valueColor: scheme.onSurface,
          ),
          const Divider(height: 10),
          _metricRow(
            context,
            label: 'Last Successful Update',
            value: _formatDateTime(report?.lastSuccessfulUpdate),
            valueColor: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _metricRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
    IconData? icon,
    Color? iconColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor ?? valueColor),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? scheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
