import 'dart:async';

import 'package:flutter/material.dart';

import 'release_contract.dart';

/// Small desktop-only status surface for THQ Client/POS chrome.
///
/// Uses the workstation's local clock so users can immediately confirm both
/// the running release and the transaction workstation time.
class DesktopReleaseStatus extends StatefulWidget {
  final bool compact;
  final EdgeInsetsGeometry padding;

  const DesktopReleaseStatus({
    super.key,
    this.compact = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  });

  @override
  State<DesktopReleaseStatus> createState() => _DesktopReleaseStatusState();
}

class _DesktopReleaseStatusState extends State<DesktopReleaseStatus> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${_two(value.minute)} $suffix';
  }

  String _date(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${_two(value.day)} ${months[value.month - 1]} ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final version =
        'v${ThqReleaseContract.appVersion} • Build ${ThqReleaseContract.buildNumber}';
    final timestamp = '${_date(_now)} • ${_time(_now)}';
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    if (widget.compact) {
      return Padding(
        padding: widget.padding,
        child: Tooltip(
          message: '$version\n$timestamp',
          child: Icon(Icons.schedule_outlined, size: 17, color: color),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            version,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: color),
          ),
        ],
      ),
    );
  }
}
