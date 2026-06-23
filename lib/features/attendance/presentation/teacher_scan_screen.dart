import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../services/supabase_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/theme_provider.dart';
import '../../../utils/responsive.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/common.dart';
import 'sync_status_screen.dart';

class TeacherScanScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final String? preselectedSubject;
  final int? preselectedSemester;

  const TeacherScanScreen({
    super.key,
    required this.profile,
    this.preselectedSubject,
    this.preselectedSemester,
  });

  @override
  State<TeacherScanScreen> createState() => _TeacherScanScreenState();
}

class _TeacherScanScreenState extends State<TeacherScanScreen> {
  MobileScannerController? _scannerController;
  bool _scannerActive = false;
  bool _processing = false;
  final _uuid = const Uuid();

  String? _subject;

  List<Map<String, dynamic>> _recentScans = [];
  bool _debouncing = false;

  @override
  void initState() {
    super.initState();
    _subject = widget.preselectedSubject;
    _loadRecent();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final records = await LocalDatabase.getAllLocalAttendance();
      if (mounted) setState(() => _recentScans = records.take(20).toList());
    } catch (_) {}
  }

  void _toggleScanner() {
    if (_scannerActive) {
      _scannerController?.stop();
      setState(() => _scannerActive = false);
    } else {
      _scannerController = MobileScannerController();
      _scannerController!.start();
      setState(() => _scannerActive = true);
    }
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_processing || _debouncing) return;
    final barcode = capture.barcodes.firstOrNull;
    final rawValue = barcode?.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    final raw = rawValue;

    String studentId;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['id'] != null) {
        studentId = parsed['id'].toString();
      } else {
        studentId = raw.trim();
      }
    } catch (_) {
      studentId = raw.trim();
    }

    if (studentId.length < 8) {
      showAppSnackbar(context, 'Invalid QR code', isError: true);
      return;
    }

    _debouncing = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _debouncing = false;
    });

    _scannerController?.stop();
    setState(() => _scannerActive = false);

    await _processStudentScan(studentId);
  }

  Future<void> _processStudentScan(String studentId) async {
    setState(() => _processing = true);

    try {
      Map<String, dynamic>? student = await LocalDatabase.getCachedStudent(studentId);

      if (student == null) {
        if (ConnectivityService().isOnline.value) {
          final remote = await SupabaseService.getStudent(studentId);
          if (remote != null) {
            student = {
              'id': remote['id']?.toString() ?? studentId,
              'name': remote['name']?.toString() ?? '',
              'roll_no': remote['roll']?.toString() ?? remote['roll_no']?.toString(),
              'class': remote['class']?.toString(),
              'section': remote['section']?.toString(),
              'photo_url': remote['photo_url']?.toString(),
            };
            await LocalDatabase.cacheStudents([student]);
          }
        }
      }

      if (student == null) {
        _showUnknownQrDialog(studentId);
        setState(() => _processing = false);
        if (_scannerActive) _scannerController?.start();
        return;
      }

      final subject = _subject ?? '';
      final now = DateTime.now().toUtc().toIso8601String();

      if (subject.isNotEmpty) {
        final duplicate = await LocalDatabase.isDuplicateScan(studentId, subject, now);
        if (duplicate) {
          _showDuplicateDialog(student['name']?.toString() ?? studentId);
          setState(() => _processing = false);
          if (_scannerActive) _scannerController?.start();
          return;
        }
      }

      final record = {
        'id': _uuid.v4(),
        'student_id': studentId,
        'student_name': student['name']?.toString() ?? '',
        'class': student['class']?.toString() ?? '',
        'subject': subject,
        'status': 'present',
        'scanned_at': now,
        'sync_status': 'pending',
        'retry_count': 0,
        'token': '',
        'method': 'teacher_scan',
        'device_id': SupabaseService.currentUser?.id ?? '',
        'created_at': now,
      };

      await LocalDatabase.insertAttendanceLocal(record);
      SyncManager().pendingCount.value = await LocalDatabase.getPendingCount();

      _showSuccessDialog(student['name']?.toString() ?? 'Student');
      await _loadRecent();

      if (ConnectivityService().isOnline.value) {
        SyncManager().manualSync();
      }
    } catch (e) {
      _showErrorDialog(friendlyError(e));
    }

    setState(() => _processing = false);
  }

  void _showSuccessDialog(String studentName) {
    final c = context.colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.accent3.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle, color: c.accent3, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Attendance Marked!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white)),
              const SizedBox(height: 8),
              Text(studentName, style: TextStyle(color: c.accent3, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Record saved offline', style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Continue Scanning',
                icon: Icons.qr_code_scanner,
                onPressed: () {
                  Navigator.pop(ctx);
                  if (mounted) _toggleScanner();
                },
              ),
            ],
          ),
        ),
      ).animate().scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack).fadeIn(duration: 250.ms),
    );
  }

  void _showDuplicateDialog(String studentName) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.accentOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.info_outline, color: c.accentOrange, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Already Marked', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.white)),
              const SizedBox(height: 8),
              Text('$studentName has already been marked present for this subject today.', style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              PrimaryButton(label: 'OK', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnknownQrDialog(String qrContent) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, color: c.danger, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Unknown QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.white)),
              const SizedBox(height: 8),
              Text('This QR code is not recognized. Please scan a valid student QR code.', style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Try Again', icon: Icons.refresh, onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorDialog(String error) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, color: c.danger, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.white)),
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Try Again', icon: Icons.refresh, onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final online = ConnectivityService().isOnline.value;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: const Text('Scan Student QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          StreamBuilder<int>(
            stream: _pendingCountStream(),
            initialData: 0,
            builder: (ctx, snap) {
              if (snap.data == null || snap.data! <= 0) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => Navigator.push(context, buildCupertinoRoute(const SyncStatusScreen())),
                  child: AppBadge(
                    label: '${snap.data} pending',
                    color: c.accentOrange,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            color: online ? c.accent : c.muted,
            onPressed: online ? () async {
              final count = await SyncManager().manualSync();
              if (mounted) showAppSnackbar(context, 'Synced $count records');
            } : null,
            tooltip: 'Sync',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject selector
            AppCard(
              borderColor: c.accent.withValues(alpha: 0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SUBJECT', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    style: TextStyle(color: c.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Data Structures',
                      hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: c.bg3,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.accent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    controller: TextEditingController(text: _subject ?? ''),
                    onChanged: (v) => _subject = v.isNotEmpty ? v : null,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0, duration: 400.ms),
            const SizedBox(height: 16),

            // Scanner section
            AppCard(
              borderColor: c.accent3.withValues(alpha: 0.2),
              child: Column(
                children: [
                  if (_scannerActive) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: MobileScanner(
                          controller: _scannerController!,
                          onDetect: _onQrDetected,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Point camera at student\'s QR code',
                      style: TextStyle(color: c.muted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    GhostButton(
                      label: 'Close Scanner',
                      icon: Icons.close,
                      color: c.danger,
                      onPressed: _toggleScanner,
                    ),
                  ] else ...[
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: c.bg3,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_scanner, size: 48, color: Colors.amber),
                            const SizedBox(height: 12),
                            Text(
                              'Tap to open camera and scan student QR',
                              style: TextStyle(color: c.muted, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Open Scanner',
                      icon: Icons.qr_code_scanner,
                      onPressed: _toggleScanner,
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.08, end: 0, duration: 400.ms, delay: 100.ms),
            const SizedBox(height: 24),

            // Recent scans
            if (_recentScans.isNotEmpty) ...[
              SectionTitle(
                title: 'Recent Scans',
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, buildCupertinoRoute(const SyncStatusScreen())),
                  child: Text('View All', style: TextStyle(color: c.accent, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 12),
              ...(_recentScans.take(5).map((r) {
                final syncStatus = r['sync_status']?.toString() ?? '';
                final isPending = syncStatus == 'pending' || syncStatus == 'failed';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c.accent3, c.accent3.withValues(alpha: 0.7)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            (r['student_name']?.toString() ?? '?')[0].toUpperCase(),
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['student_name']?.toString() ?? '', style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(r['subject']?.toString() ?? '', style: TextStyle(color: c.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      if (isPending)
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: c.accentOrange, shape: BoxShape.circle),
                        )
                      else
                        Icon(Icons.check_circle, color: c.accent3, size: 16),
                    ],
                  ),
                );
              })),
            ],
          ],
        ),
      ),
    );
  }

  Stream<int> _pendingCountStream() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      yield SyncManager().pendingCount.value;
    }
  }
}
