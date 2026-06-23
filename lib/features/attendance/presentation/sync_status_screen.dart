import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/theme_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/common.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    ConnectivityService().isOnline.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService().isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (ConnectivityService().isOnline.value) {
      _autoSync();
    }
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final records = await LocalDatabase.getAllLocalAttendance();
      if (mounted) setState(() { _records = records; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _autoSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await SyncManager().manualSync();
      await _loadRecords();
    } catch (_) {}
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _manualSync() async {
    if (_syncing) return;
    if (!ConnectivityService().isOnline.value) {
      showAppSnackbar(context, 'Can\'t sync while offline — will sync automatically when connected', isError: true);
      return;
    }
    setState(() => _syncing = true);
    try {
      final count = await SyncManager().manualSync();
      await _loadRecords();
      if (mounted) showAppSnackbar(context, 'Synced $count records');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _syncing = false);
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final online = ConnectivityService().isOnline.value;
    final pendingCount = _records.where((r) => r['sync_status'] == 'pending' || r['sync_status'] == 'failed').length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: const Text('Sync Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: AppBadge(
                  label: '$pendingCount pending',
                  color: c.accentOrange,
                ),
              ),
            ),
          IconButton(
            icon: _syncing
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                : Icon(Icons.sync, color: online ? c.accent : c.muted),
            onPressed: online ? _manualSync : null,
            tooltip: 'Sync now',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_syncing)
            LinearProgressIndicator(backgroundColor: c.bg3, color: c.accent),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const EmptyState(icon: Icons.check_circle_outline, title: 'All Synced', subtitle: 'No pending attendance records')
                    : RefreshIndicator(
                        onRefresh: _loadRecords,
                        child: ListView.builder(
                          padding: EdgeInsets.all(Responsive.screenPadding(context)),
                          itemCount: _records.length,
                          itemBuilder: (ctx, i) {
                            final r = _records[i];
                            final syncStatus = r['sync_status']?.toString() ?? 'pending';
                            final isPending = syncStatus == 'pending';
                            final isFailed = syncStatus == 'failed';

                            Color statusColor;
                            IconData statusIcon;
                            String statusLabel;

                            if (isPending) {
                              statusColor = c.accentOrange;
                              statusIcon = Icons.sync;
                              statusLabel = 'Pending';
                            } else if (isFailed) {
                              statusColor = c.danger;
                              statusIcon = Icons.error_outline;
                              statusLabel = 'Failed';
                            } else {
                              statusColor = c.accent3;
                              statusIcon = Icons.check_circle;
                              statusLabel = 'Synced';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isFailed ? c.danger.withValues(alpha: 0.3) : c.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(statusIcon, color: statusColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r['student_name']?.toString() ?? 'Unknown',
                                          style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${r['subject'] ?? ''} · ${_formatDate(r['scanned_at'] ?? r['created_at'] ?? '')}',
                                          style: TextStyle(color: c.muted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AppBadge(label: statusLabel, color: statusColor),
                                ],
                              ),
                            ).animate(delay: Duration(milliseconds: (i * 40).clamp(0, 400)))
                                .fadeIn(duration: 300.ms)
                                .slideX(begin: 0.1, end: 0, duration: 300.ms);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
