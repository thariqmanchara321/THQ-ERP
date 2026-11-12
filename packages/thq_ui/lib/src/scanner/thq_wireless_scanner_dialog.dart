import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../components/thq_buttons.dart';
import '../components/thq_card.dart';
import '../components/thq_dialog.dart';
import '../foundations/thq_tokens.dart';
import 'thq_pairing_qr_view.dart';

/// Modal dialog displayed on desktop applications (POS Desktop & Client Desktop)
/// to show the pairing QR code, session countdown, paired phone details, and unpair controls.
class ThqWirelessScannerDialog extends StatefulWidget {
  final WirelessScannerCoordinator coordinator;
  final String tenantId;
  final String? locationId;
  final String hostDeviceName;

  const ThqWirelessScannerDialog({
    super.key,
    required this.coordinator,
    required this.tenantId,
    this.locationId,
    this.hostDeviceName = 'Desktop Workstation',
  });

  /// Static helper to display the wireless scanner dialog.
  static Future<void> show({
    required BuildContext context,
    required WirelessScannerCoordinator coordinator,
    required String tenantId,
    String? locationId,
    String hostDeviceName = 'Desktop Workstation',
  }) {
    return showThqDialog<void>(
      context: context,
      builder: (_) => ThqWirelessScannerDialog(
        coordinator: coordinator,
        tenantId: tenantId,
        locationId: locationId,
        hostDeviceName: hostDeviceName,
      ),
    );
  }

  @override
  State<ThqWirelessScannerDialog> createState() =>
      _ThqWirelessScannerDialogState();
}

class _ThqWirelessScannerDialogState extends State<ThqWirelessScannerDialog> {
  late WirelessScannerState _state;
  WirelessScannerDevice? _device;
  StreamSubscription<WirelessScannerState>? _stateSub;
  StreamSubscription<WirelessScannerDevice?>? _deviceSub;
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _state = widget.coordinator.state;
    _device = widget.coordinator.activeDevice;

    _stateSub = widget.coordinator.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });

    _deviceSub = widget.coordinator.deviceStream.listen((d) {
      if (mounted) setState(() => _device = d);
    });

    _initOrRefreshSession();
    _startCountdown();
  }

  Future<void> _initOrRefreshSession() async {
    final payload = widget.coordinator.currentPayload;
    if (payload == null || payload.isExpired) {
      setState(() => _isGenerating = true);
      try {
        await widget.coordinator.startHostingSession(
          tenantId: widget.tenantId,
          locationId: widget.locationId,
          hostDeviceName: widget.hostDeviceName,
          expiration: const Duration(minutes: 10),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isGenerating = false;
            _updateSecondsRemaining();
          });
        }
      }
    } else {
      _updateSecondsRemaining();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_updateSecondsRemaining);
      }
    });
  }

  void _updateSecondsRemaining() {
    final payload = widget.coordinator.currentPayload;
    if (payload == null) {
      _secondsRemaining = 0;
    } else {
      final diff = payload.expiresAt.difference(DateTime.now()).inSeconds;
      _secondsRemaining = diff > 0 ? diff : 0;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stateSub?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }

  String _formatTimer(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _state == WirelessScannerState.connected ||
        widget.coordinator.isConnected;
    final payload = widget.coordinator.currentPayload;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Colors.green.withAlpha(30)
                          : theme.colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isConnected
                          ? Icons.phone_android
                          : Icons.qr_code_scanner,
                      color: isConnected
                          ? Colors.green
                          : theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phone-to-PC Wireless Scanner',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isConnected
                              ? 'Active connection established'
                              : 'Pair with mobile scanner',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(160),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Content Body
              Expanded(
                child: SingleChildScrollView(
                  child: isConnected
                      ? _buildConnectedView(theme)
                      : _buildPairingView(theme, payload),
                ),
              ),

              const SizedBox(height: 16),
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isConnected) ...[
                    ThqSecondaryButton(
                      label: 'Unpair Phone',
                      icon: Icons.link_off,
                      onPressed: () async {
                        await widget.coordinator.unpair();
                        await _initOrRefreshSession();
                      },
                    ),
                    const SizedBox(width: 12),
                  ],
                  ThqPrimaryButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPairingView(
      ThemeData theme, WirelessScannerPairingPayload? payload) {
    if (_isGenerating || payload == null) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isExpired = _secondsRemaining <= 0;

    return Column(
      children: [
        // QR Code or Expiration Notice
        if (isExpired)
          Container(
            height: 220,
            width: 220,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withAlpha(80)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_off_outlined,
                    color: Colors.red, size: 48),
                const SizedBox(height: 8),
                const Text(
                  'Pairing Session Expired',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ThqPrimaryButton(
                  label: 'Generate New QR',
                  icon: Icons.refresh,
                  onPressed: _initOrRefreshSession,
                ),
              ],
            ),
          )
        else
          ThqPairingQrView(
            data: payload.toQrString(),
            size: 210,
          ),

        const SizedBox(height: 14),

        // Countdown timer badge
        if (!isExpired)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(ThqTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _secondsRemaining < 60
                      ? Colors.orange
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Valid for ${_formatTimer(_secondsRemaining)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _secondsRemaining < 60 ? Colors.orange : null,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _initOrRefreshSession,
                  child: const Icon(Icons.refresh, size: 16),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Instructions
        ThqCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How to connect:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              _buildStepRow(theme, '1', 'Open THQ Mobile on your phone'),
              const SizedBox(height: 4),
              _buildStepRow(
                  theme, '2', 'Tap "Wireless Scanner" and scan this QR code'),
              const SizedBox(height: 4),
              _buildStepRow(
                  theme, '3', 'Barcodes scanned on phone appear here instantly'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow(ThemeData theme, String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedView(ThemeData theme) {
    final dev = _device ?? widget.coordinator.activeDevice;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 44,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          dev?.deviceName ?? 'Mobile Device',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Paired and ready to scan',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.green,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        ThqCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildInfoRow('Device ID', dev?.deviceId ?? 'Unknown'),
              const Divider(height: 16),
              _buildInfoRow(
                  'Scans Received', '${dev?.scansSent ?? 0} items'),
              const Divider(height: 16),
              _buildInfoRow('Transport Protocol', 'Supabase Realtime Broadcast'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You can close this dialog. Incoming scans from your phone will continue feeding into your active screen.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
