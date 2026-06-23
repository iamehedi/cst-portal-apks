import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../services/cache_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/routine_service.dart';
import '../../../utils/theme_provider.dart';
import '../../../utils/responsive.dart';
import '../../../utils/pdf_export.dart';
import '../../../widgets/common.dart';
import '../providers/ble_session_provider.dart';

class TeacherBleSessionScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final String? initialSubject;
  final int? initialSemester;

  const TeacherBleSessionScreen({
    super.key,
    required this.profile,
    this.initialSubject,
    this.initialSemester,
  });

  @override
  State<TeacherBleSessionScreen> createState() => _TeacherBleSessionScreenState();
}

class _TeacherBleSessionScreenState extends State<TeacherBleSessionScreen> {
  String? _selectedSubject;
  int _semester = 3;
  List<Map<String, dynamic>> _allRoutineSlots = [];
  List<Map<String, dynamic>> _todaySlots = [];
  bool _loadingRoutines = true;

  static const _dayMap = {
    1: 'MON', 2: 'TUE', 3: 'WED', 4: 'THU', 5: 'FRI', 6: 'SAT', 7: 'SUN',
  };
  static const _periodTimes = [
    '1:30 – 2:15 PM',
    '2:15 – 3:00 PM',
    '3:00 – 3:45 PM',
    '3:45 – 4:30 PM',
    '4:30 – 5:15 PM',
    '5:15 – 6:00 PM',
    '6:00 – 6:45 PM',
    '1:30 – 3:45 PM (2h 15m)',
    '2:15 – 4:30 PM (2h 15m)',
    '3:00 – 5:15 PM (2h 15m)',
    '3:45 – 6:00 PM (2h 15m)',
    '4:30 – 6:45 PM (2h 15m)',
  ];

  @override
  void initState() {
    super.initState();
    _selectedSubject = widget.initialSubject;
    _semester = widget.initialSemester ?? 3;
    _loadFromCache();
    _loadRoutines();
  }

  void _loadFromCache() {
    final cacheKey = CacheService.routineKey(_semester);
    if (CacheService.isStale(cacheKey)) return;
    final cached = CacheService.loadList(cacheKey);
    if (cached == null || cached.isEmpty) return;
    setState(() {
      _allRoutineSlots = cached;
      _filterSlotsForDate();
      _loadingRoutines = false;
    });
  }

  Future<void> _loadRoutines() async {
    if (!ConnectivityService().isOnline.value) return;
    setState(() => _loadingRoutines = true);
    try {
      final routines = await RoutineService.fetch(_semester);
      if (!mounted) return;
      final rows = routines.map((slot) => slot.toRow()).toList();
      CacheService.saveList(CacheService.routineKey(_semester), rows);
      setState(() {
        _allRoutineSlots = rows;
        _filterSlotsForDate();
        _loadingRoutines = false;
      });
    } catch (_) {
      if (mounted) setState(() { _filterSlotsForDate(); _loadingRoutines = false; });
    }
  }

  void _filterSlotsForDate() {
    final dayCode = _dayMap[DateTime.now().weekday] ?? '';
    _todaySlots = _allRoutineSlots
        .where((r) => RoutineService.normalizeDay(r['day']?.toString()) == dayCode)
        .toList();
    if (_todaySlots.isNotEmpty && (_selectedSubject == null || !_todaySlots.any((s) => s['subject']?.toString() == _selectedSubject))) {
      _selectedSubject = _todaySlots.first['subject']?.toString();
      _semester = int.tryParse(_todaySlots.first['semester']?.toString() ?? '') ?? _semester;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;

    if (kIsWeb) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.white,
          title: const Text('Smart Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 48, color: c.warn),
                const SizedBox(height: 16),
                Text('Smart Attendance not supported on Web',
                    style: TextStyle(color: c.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Please use an Android device to run Smart attendance sessions.',
                    style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final provider = context.watch<BleSessionProvider>();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: Text(
          provider.status == 'active' ? 'Live Session' : 'Smart Attendance',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (provider.status == 'active') ...[
            IconButton(
              onPressed: provider.roster.isEmpty ? null : () => _exportPdf(provider),
              icon: Icon(Icons.picture_as_pdf, color: c.accent),
              tooltip: 'Export PDF',
            ),
            TextButton(
              onPressed: () => _confirmStop(context, provider),
              child: Text('Stop', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      body: provider.status == 'active' ? _buildLiveSession(context, provider) : _buildStartForm(context, provider),
    );
  }

  Widget _buildStartForm(BuildContext context, BleSessionProvider provider) {
    final c = context.colorsOf;

    return SingleChildScrollView(
      padding: EdgeInsets.all(Responsive.screenPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start Smart Attendance Session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white)),
          const SizedBox(height: 8),
          Text('Your device will broadcast a beacon. Students in range will auto-detect and check in.',
              style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 24),

          Text('SUBJECT — TODAY\'S ROUTINE', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_loadingRoutines)
            const ShimmerBox(height: 48)
          else if (_todaySlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: c.bg3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Text(
                'No classes scheduled for today',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            )
          else
            ..._todaySlots.map((slot) {
              final subj = slot['subject']?.toString() ?? '';
              final teacher = slot['teacher']?.toString() ?? '';
              final pIdx = int.tryParse(slot['period_index']?.toString() ?? '') ?? 0;
              final room = slot['room']?.toString() ?? '';
              final timeStr = pIdx < _periodTimes.length ? _periodTimes[pIdx] : 'Period ${pIdx + 1}';
              final isSelected = _selectedSubject == subj;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSubject = subj;
                    _semester = int.tryParse(slot['semester']?.toString() ?? '') ?? _semester;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? c.accent.withValues(alpha: 0.1) : c.bg3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? c.accent : c.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? c.accent.withValues(alpha: 0.2) : c.bg2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'P${pIdx + 1}',
                            style: TextStyle(
                              color: isSelected ? c.accent : c.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(subj, style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(
                              timeStr,
                              style: TextStyle(color: isSelected ? c.accent : c.muted, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            if (teacher.isNotEmpty || room.isNotEmpty)
                              Text(
                                [teacher, if (room.isNotEmpty) 'Room $room'].where((s) => s.isNotEmpty).join(' · '),
                                style: TextStyle(color: c.muted, fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: c.accent, size: 20),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 24),

          if (provider.loading)
            const Center(child: CircularProgressIndicator())
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startSession(context, provider),
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Start Attendance'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          if (provider.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: c.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(provider.error!, style: TextStyle(color: c.danger, fontSize: 12))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveSession(BuildContext context, BleSessionProvider provider) {
    final c = context.colorsOf;

    return Column(
      children: [
        if (provider.isBluetoothOff)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: c.danger, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bluetooth Off',
                          style: TextStyle(color: c.danger, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('Students cannot check in while Bluetooth is off.',
                          style: TextStyle(color: c.muted, fontSize: 11)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => provider.retrySession(),
                  child: Text('Retry', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.accent.withValues(alpha: 0.15), c.accent.withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: c.accent2,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.accent2.withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Session Active', style: TextStyle(color: c.accent2, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Text(provider.subject ?? '', style: TextStyle(color: c.white, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('Semester ${provider.semester ?? ''}',
                  style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBadge(c, 'Connected', '${provider.connectedCount}', c.accent),
                  _StatBadge(c, 'Detected', '${provider.roster.length}', c.white),
                  _StatBadge(c, 'Pending', '${provider.pendingCount}', Colors.orange),
                ],
              ),
            ],
          ),
        ),

        if (provider.pendingCount > 0 && !provider.approving)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => provider.approveAll(),
                icon: const Icon(Icons.check_circle, size: 18),
                label: Text('Approve All (${provider.pendingCount})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),

        if (provider.approving)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: provider.approveTotal > 0
                      ? provider.approveProgress / provider.approveTotal
                      : null,
                  backgroundColor: c.bg3,
                  color: Colors.green,
                ),
                const SizedBox(height: 4),
                Text('Approving ${provider.approveProgress}/${provider.approveTotal}...',
                    style: TextStyle(color: c.muted, fontSize: 11)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Live Roster', style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text('${provider.roster.length} students', style: TextStyle(color: c.muted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: provider.roster.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth_searching, size: 48, color: c.muted),
                      const SizedBox(height: 12),
                      Text('Waiting for students...', style: TextStyle(color: c.muted, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Students nearby will appear here automatically',
                          style: TextStyle(color: c.muted.withValues(alpha: 0.6), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.roster.length,
                  itemBuilder: (context, index) {
                    final student = provider.roster[index];
                    return _buildRosterItem(c, student, provider);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRosterItem(ThemeColors c, BlePendingStudent student, BleSessionProvider provider) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (student.status) {
      case 'present':
        statusColor = Colors.green;
        statusLabel = 'Present';
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = c.danger;
        statusLabel = 'Rejected';
        statusIcon = Icons.cancel;
        break;
      case 'disconnected':
        statusColor = Colors.orange;
        statusLabel = 'Disconnected';
        statusIcon = Icons.link_off;
        break;
      default:
        statusColor = c.warn;
        statusLabel = 'Pending';
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bg3,
        borderRadius: BorderRadius.circular(10),
        border: student.status == 'pending' ? Border.all(color: c.warn.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.studentName, style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(student.studentId, style: TextStyle(color: c.muted, fontSize: 11)),
              ],
            ),
          ),
          if (student.status == 'pending')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => provider.approveStudent(student.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Approve', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => provider.rejectStudent(student.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Reject', style: TextStyle(color: c.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            )
          else
            Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _StatBadge(ThemeColors c, String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
      ],
    );
  }

  Future<void> _exportPdf(BleSessionProvider provider) async {
    if (provider.roster.isEmpty) return;

    final roster = provider.roster.map((s) => (
      studentId: s.studentId,
      studentName: s.studentName,
      status: s.status,
    )).toList();

    try {
      final bytes = await PdfExport.generateBleSessionPdf(
        subject: provider.subject ?? 'Unknown',
        semester: provider.semester ?? 0,
        roster: roster,
      );
      final fileName = 'BLE_Attendance_${provider.subject?.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await PdfExport.sharePdf(bytes, fileName);
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Failed to generate PDF: $e', isError: true);
      }
    }
  }

  Future<void> _startSession(BuildContext context, BleSessionProvider provider) async {
    final subject = _selectedSubject;
    if (subject == null || subject.isEmpty) {
      showAppSnackbar(context, 'Please select a subject from today\'s routine', isError: true);
      return;
    }
    final teacherId = widget.profile['id']?.toString() ?? widget.profile['user_id']?.toString() ?? '';
    final department = widget.profile['department']?.toString() ?? '';

    final ok = await provider.startSession(
      subject: subject,
      semester: _semester,
      teacherId: teacherId,
      department: department,
    );

    if (ok) {
      showAppSnackbar(context, 'Session started! Students can now check in.', isError: false);
    }
  }

  Future<void> _confirmStop(BuildContext context, BleSessionProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colorsOf.bg3,
        title: Text('Stop Session?', style: TextStyle(color: context.colorsOf.white)),
        content: Text('Pending students will be marked as rejected.',
            style: TextStyle(color: context.colorsOf.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.colorsOf.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Stop', style: TextStyle(color: context.colorsOf.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.stopSession();
      if (!mounted) return;
      final exportPdf = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.colorsOf.bg3,
          title: Text('Export Report?', style: TextStyle(color: context.colorsOf.white)),
          content: Text('Do you want to save the attendance report as PDF?',
              style: TextStyle(color: context.colorsOf.muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('No', style: TextStyle(color: context.colorsOf.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Yes', style: TextStyle(color: context.colorsOf.accent)),
            ),
          ],
        ),
      );
      if (exportPdf == true && mounted) {
        await _exportPdf(provider);
      }
      if (mounted) {
        showAppSnackbar(context, 'Session closed', isError: false);
      }
    }
  }
}
