import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobileStaffAttendancePage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileStaffAttendancePage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileStaffAttendancePage> createState() =>
      _MobileStaffAttendancePageState();
}

class _MobileStaffAttendancePageState extends State<MobileStaffAttendancePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  DateTime _attendanceDate = DateTime.now();
  late Future<Map<String, dynamic>> _staffFuture;

  // Local attendance state for the active date: staffId -> {status, hours, overtime}
  final Map<String, Map<String, dynamic>> _attendanceMap = {};
  bool _savingAttendance = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    final locId = widget.locationId ?? widget.session.locationId;
    _staffFuture = widget.service.staffAction(
      widget.session,
      action: 'list',
      locationId: locId,
      data: {'status': 'active'},
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _staffFuture;
  }

  void _recordStaffPayment(Map<String, dynamic> staff) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String method = 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Pay Staff: ${staff['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Payment Amount *',
                  prefixText: '${widget.session.currency} ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => method = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: 'Notes / Purpose',
                  hintText: 'Advance, wage settlement, etc.',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amt <= 0) {
                  ThqNotify.error(context, 'Validation', message: 'Enter a valid amount.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final locId = widget.locationId ?? widget.session.locationId;
        final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
        await widget.service.staffAction(
          widget.session,
          action: 'payment',
          locationId: locId,
          data: {
            'staff_id': staff['id'],
            'amount': amt,
            'payment_method': method,
            'notes': noteCtrl.text.trim(),
            'payment_date': '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
          },
        );
        if (!mounted) return;
        ThqNotify.success(context, 'Payment Recorded', message: 'Staff payment recorded.');
        _refresh();
      } catch (e) {
        if (!mounted) return;
        ThqNotify.error(context, 'Payment Failed', message: '$e');
      }
    }
  }

  Future<void> _saveAttendanceForStaff(Map<String, dynamic> staff, String status) async {
    final staffId = staff['id']?.toString() ?? '';
    final locId = widget.locationId ?? widget.session.locationId;
    final dateStr = '${_attendanceDate.year}-${_attendanceDate.month.toString().padLeft(2, '0')}-${_attendanceDate.day.toString().padLeft(2, '0')}';

    setState(() {
      _attendanceMap[staffId] = {
        'status': status,
        'hours': status == 'present' ? 8.0 : (status == 'half_day' ? 4.0 : 0.0),
        'overtime_hours': 0.0,
      };
    });

    try {
      await widget.service.staffAction(
        widget.session,
        action: 'attendance',
        locationId: locId,
        data: {
          'staff_id': staffId,
          'work_date': dateStr,
          'status': status,
          'hours': status == 'present' ? 8.0 : (status == 'half_day' ? 4.0 : 0.0),
          'overtime_hours': 0.0,
        },
      );
    } catch (e) {
      if (mounted) {
        ThqNotify.error(context, 'Attendance Error', message: '$e');
      }
    }
  }

  void _markAllPresent(List<Map<String, dynamic>> staffList) async {
    setState(() => _savingAttendance = true);
    for (final s in staffList) {
      await _saveAttendanceForStaff(s, 'present');
    }
    if (mounted) {
      setState(() => _savingAttendance = false);
      ThqNotify.success(context, 'Marked Present', message: 'All staff marked present.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Attendance'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.badge_outlined), text: 'Staff Directory'),
            Tab(icon: Icon(Icons.how_to_reg_outlined), text: 'Daily Attendance'),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _staffFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const WorkspaceLoadingList();
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 40, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 10),
                    Text('Failed to load staff: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _refresh, child: const Text('Try Again')),
                  ],
                ),
              ),
            );
          }

          final rawStaff = (snapshot.data?['staff'] as List? ?? const []).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildDirectoryTab(rawStaff),
              _buildAttendanceTab(rawStaff),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDirectoryTab(List<Map<String, dynamic>> staffList) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = staffList.where((s) {
      if (query.isEmpty) return true;
      final name = (s['name'] ?? '').toString().toLowerCase();
      final role = (s['designation'] ?? s['role'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      return name.contains(query) || role.contains(query) || phone.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search staff by name, role or phone...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No staff records found'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final name = item['name'] ?? 'Staff Member';
                    final role = item['designation'] ?? item['role'] ?? 'Worker';
                    final phone = item['phone'] ?? '';
                    final advance = item['advance_balance'] ?? 0;
                    final currency = widget.session.currency;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$role${phone.isNotEmpty ? " • $phone" : ""}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  if ((advance as num) > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Advance: $currency ${(advance).toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _recordStaffPayment(item),
                              icon: const Icon(Icons.payment_rounded, size: 16),
                              label: const Text('Pay'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAttendanceTab(List<Map<String, dynamic>> staffList) {
    final dateStr = '${_attendanceDate.year}-${_attendanceDate.month.toString().padLeft(2, '0')}-${_attendanceDate.day.toString().padLeft(2, '0')}';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _attendanceDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (picked != null && mounted) {
                    setState(() => _attendanceDate = picked);
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _savingAttendance ? null : () => _markAllPresent(staffList),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('All Present'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
        Expanded(
          child: staffList.isEmpty
              ? const Center(child: Text('No active staff registered'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: staffList.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = staffList[i];
                    final staffId = item['id']?.toString() ?? '';
                    final name = item['name'] ?? 'Staff';
                    final role = item['designation'] ?? 'Staff';
                    final currentStatus = _attendanceMap[staffId]?['status'] ?? 'pending';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(role, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Present'),
                                    selected: currentStatus == 'present',
                                    selectedColor: Colors.green.shade100,
                                    onSelected: (_) => _saveAttendanceForStaff(item, 'present'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('Half-Day'),
                                    selected: currentStatus == 'half_day',
                                    selectedColor: Colors.orange.shade100,
                                    onSelected: (_) => _saveAttendanceForStaff(item, 'half_day'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('Absent'),
                                    selected: currentStatus == 'absent',
                                    selectedColor: Colors.red.shade100,
                                    onSelected: (_) => _saveAttendanceForStaff(item, 'absent'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('Leave'),
                                    selected: currentStatus == 'leave',
                                    selectedColor: Colors.blue.shade100,
                                    onSelected: (_) => _saveAttendanceForStaff(item, 'leave'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
