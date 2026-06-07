import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../services/supabase_service.dart';
import '../utils/pdf_export.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';

class StudentAttendanceHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentAttendanceHistoryScreen({super.key, required this.profile});

  @override
  State<StudentAttendanceHistoryScreen> createState() => _StudentAttendanceHistoryScreenState();
}

class _StudentAttendanceHistoryScreenState extends State<StudentAttendanceHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _stats = [];
  bool _loading = true;
  String? _error;

  String get _studentId => (widget.profile['roll'] ?? '').toString();
  String get _studentName => (widget.profile['name'] ?? 'Student').toString();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AttendanceService.getStudentAttendance(_studentId);
      if (!mounted) return;
      if (result.containsKey('error')) {
        setState(() {
          _error = result['error']?.toString() ?? 'Failed to load';
          _loading = false;
        });
        return;
      }
      setState(() {
        _records = List<Map<String, dynamic>>.from(result['records'] ?? []);
        _stats = List<Map<String, dynamic>>.from(result['stats'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: const Text('My Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: Icon(Icons.picture_as_pdf, color: c.accent),
              onPressed: _exportPdf,
              tooltip: 'Download PDF',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetch,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(c),
    );
  }

  Widget _buildBody(ThemeColors c) {
    if (_loading) {
      return ListView.builder(
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        itemCount: 5,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: ShimmerBox(height: 80),
        ),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        color: c.accent,
        onRefresh: _fetch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: _error ?? 'Unknown error',
            ),
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return RefreshIndicator(
        color: c.accent,
        onRefresh: _fetch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: const EmptyState(
              icon: Icons.history,
              title: 'No attendance records yet',
              subtitle: 'Mark your attendance in class to see it here',
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: c.accent,
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student info summary
            _buildStudentInfo(c),
            const SizedBox(height: 20),

            // Subject-wise stats
            if (_stats.isNotEmpty) ...[
              const SectionTitle(title: 'Attendance by Subject', icon: Icons.bar_chart),
              const SizedBox(height: 12),
              ..._stats.asMap().entries.map((entry) => _buildSubjectCard(c, entry.value, entry.key)),
              const SizedBox(height: 24),
            ],

            // Record list
            const SectionTitle(title: 'Recent Records', icon: Icons.list),
            const SizedBox(height: 12),
            ..._records.asMap().entries.map((entry) => _buildRecordRow(c, entry.value, entry.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentInfo(ThemeColors c) {
    return AppCard(
      borderColor: c.accent.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.accent, c.accentDim]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _studentName.isNotEmpty ? _studentName[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_studentName, style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 14)),
                Text('ID: $_studentId', style: TextStyle(color: c.muted, fontSize: 12)),
                Text('${_stats.length} subject(s) · ${_records.length} total entries',
                    style: TextStyle(color: c.accent, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  Widget _buildSubjectCard(ThemeColors c, Map<String, dynamic> stat, int index) {
    final subject = stat['subject']?.toString() ?? 'Unknown';
    final attended = stat['attended'] as int? ?? 0;
    final total = stat['total_sessions'] as int? ?? 0;
    final pct = stat['percentage'] as int? ?? 0;
    final below75 = pct < 75;
    final barColor = below75 ? c.danger : (pct >= 90 ? c.accent3 : c.accentOrange);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: below75 ? c.danger.withValues(alpha: 0.2) : c.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(subject,
                    style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    color: barColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: c.bg3,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct / 100.0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        barColor.withValues(alpha: 0.7),
                        barColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$attended / $total sessions',
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
          if (below75)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: c.danger),
                  const SizedBox(width: 4),
                  Text('Below 75% BTEB threshold',
                      style: TextStyle(color: c.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: (index * 60).clamp(0, 400)))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.04, end: 0, duration: 300.ms, curve: Curves.easeOutQuad);
  }

  Future<void> _exportPdf() async {
    try {
      showAppSnackbar(context, 'Generating PDF...');
      final bytes = await PdfExport.generateStudentPdf(
        studentName: _studentName,
        studentId: _studentId,
        records: _records,
        stats: _stats,
      );
      final dateStr = DateFormat('dd_MMM_yyyy').format(DateTime.now());
      final fileName = 'My_Attendance_$dateStr.pdf';
      await PdfExport.sharePdf(bytes, fileName);
      if (mounted) showAppSnackbar(context, 'PDF shared successfully');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _deleteRecord(String recordId) async {
    final c = context.colors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: c.danger, size: 22),
            const SizedBox(width: 10),
            Text('Delete Record', style: TextStyle(color: c.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this attendance record?\n\nThis cannot be undone.',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await AttendanceService.deleteAttendanceRecord(recordId);
      if (mounted) {
        showAppSnackbar(context, '\u2705 Record deleted');
        _fetch();
      }
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Widget _buildRecordRow(ThemeColors c, Map<String, dynamic> record, int index) {
    final subject = record['subject']?.toString() ?? '';
    final method = (record['method']?.toString() ?? '').toUpperCase();
    final isQr = method == 'QR';
    final semester = record['semester'];
    final semStr = semester != null ? SupabaseService.semesterFromInt(int.tryParse(semester.toString()) ?? 0) : '';
    final markedAt = record['marked_at']?.toString() ?? '';
    final recordId = record['id']?.toString() ?? '';

    String time = '';
    if (markedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(markedAt).toLocal();
        time = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
      } catch (_) {
        time = markedAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isQr ? c.accent3 : c.accentOrange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isQr ? Icons.phone_android : Icons.edit,
              color: isQr ? c.accent3 : c.accentOrange,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject,
                    style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                if (semStr.isNotEmpty)
                  Text(semStr, style: TextStyle(color: c.muted, fontSize: 11)),
                Text(time, style: TextStyle(color: c.muted, fontSize: 10)),
              ],
            ),
          ),
          AppBadge(label: isQr ? 'QR' : 'MANUAL', color: isQr ? c.accent3 : c.accentOrange),
          if (recordId.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _deleteRecord(recordId),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.delete_outline, size: 16, color: c.danger),
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: Duration(milliseconds: (index * 30).clamp(0, 500)))
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.03, end: 0, duration: 250.ms);
  }
}
