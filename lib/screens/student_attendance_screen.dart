import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/ble/nearby_service.dart';
import '../core/sync/sync_manager.dart';
import '../services/attendance_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../utils/page_transitions.dart';
import '../widgets/common.dart';
import '../features/attendance/presentation/sync_status_screen.dart';
import '../features/ble/presentation/student_ble_listener_screen.dart';
import 'student_attendance_history_screen.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentAttendanceScreen({super.key, required this.profile});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  final _tokenCtrl = TextEditingController();
  bool _submitting = false;
  bool _scannerActive = false;
  MobileScannerController? _scannerController;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  String get _studentId => (widget.profile['roll'] ?? '').toString();
  String get _studentName => (widget.profile['name'] ?? 'Student').toString();

  Future<void> _submitAttendance(String token, String method, {String? sessionId}) async {
    if (token.trim().length < 6) {
      showAppSnackbar(context, 'Please enter a valid 6-character token', isError: true);
      return;
    }

    setState(() => _submitting = true);

    try {
      final result = await AttendanceService.markAttendanceOfflineFirst(
        sessionId: null,
        token: token.trim().toUpperCase(),
        studentId: _studentId,
        studentName: _studentName,
        method: method,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        _tokenCtrl.clear();
        final isOffline = result['offline'] == true;
        if (isOffline && sessionId != null) {
          // Offline + session ID available → try BLE bridge
          await _showBleBridgeDialog(sessionId, token.trim().toUpperCase());
        } else if (isOffline) {
          showAppSnackbar(context, 'Saved offline. Will sync when online.');
          _showOfflineSuccessDialog();
        } else {
          showAppSnackbar(context, 'Attendance marked successfully!');
          _showSuccessDialog(result);
        }
      } else {
        final errMsg = result['error']?.toString() ?? 'Unknown error';
        showAppSnackbar(context, errMsg, isError: true);
        _showErrorDialog(errMsg);
      }
    } catch (e) {
      if (mounted) _showErrorDialog(friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    final c = context.colors;
    final subject = result['subject']?.toString() ?? '';
    final semester = result['semester'];
    final semStr = semester != null ? SupabaseService.semesterFromInt(int.tryParse(semester.toString())) : '';

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
              Text(
                'Attendance Marked!',                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.white,
                  ),
              ),
              const SizedBox(height: 16),
              if (subject.isNotEmpty) _infoRow(c, 'Subject', subject),
              if (semStr.isNotEmpty) _infoRow(c, 'Semester', semStr),
              _infoRow(c, 'Student ID', _studentId),
              _infoRow(c, 'Name', _studentName),
              _infoRow(c, 'Time', _formatNow()),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Done',
                icon: Icons.check,
                onPressed: () {
                  Navigator.pop(ctx);
                  _tokenCtrl.clear();
                },
              ),
            ],
          ),
        ),
      ).animate().scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack).fadeIn(duration: 250.ms),
    );
  }

  Widget _infoRow(ThemeColors c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label:', style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(color: c.white, fontSize: 13, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  /// Try to deliver the QR offline check-in via BLE to the teacher's device.
  /// Shows a connecting dialog while attempting, then replaces it with
  /// either a success or fallback dialog based on the result.
  Future<void> _showBleBridgeDialog(String sessionId, String token) async {
    final c = context.colors;

    // Show connecting dialog
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
                  color: c.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: c.accent,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connecting via Bluetooth...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Sending your attendance to the\nteacher\'s device using Bluetooth.',
                style: TextStyle(color: c.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ).animate()
          .scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 250.ms),
    );

    // Try BLE bridge in the background
    final success = await NearbyService().startQrDiscovery(
      studentName: _studentName,
      studentId: _studentId,
      sessionId: sessionId,
      sessionToken: token,
    );

    await NearbyService().stopAll();

    if (!mounted) return;

    // Pop connecting dialog and show result
    Navigator.pop(context);

    if (success) {
      _showBleSuccessDialog();
    } else {
      _showOfflineSuccessDialog();
    }
  }

  /// Simple success dialog after BLE bridge delivered the check-in.
  void _showBleSuccessDialog() {
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
                child: const Icon(Icons.bluetooth_connected, color: Colors.green, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                'Teacher Received Check-in!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Your attendance was delivered via Bluetooth.\nThe teacher can see you in Live Attendance now.',
                style: TextStyle(color: c.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Done',
                icon: Icons.check,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ).animate()
          .scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 250.ms),
    );
  }

  void _showOfflineSuccessDialog() {
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
                  color: c.accentOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.wifi_off, color: c.accentOrange, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Saved Offline', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white)),
              const SizedBox(height: 8),
              Text('Attendance recorded locally.\nIt will sync automatically when online.', style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Done',
                icon: Icons.check,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ).animate().scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack).fadeIn(duration: 250.ms),
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
              Text(
                'Failed to Mark',                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.white,
                  ),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: c.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Try Again',
                icon: Icons.refresh,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_submitting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final raw = barcode!.rawValue!;
    // QR format: "sessionId|token"
    final parts = raw.split('|');
    if (parts.length == 2 && parts[1].length == 6) {
      _scannerController?.stop();
      setState(() => _scannerActive = false);
      final sessionId = parts[0];
      await _submitAttendance(parts[1], 'qr', sessionId: sessionId);
    } else {
      showAppSnackbar(context, 'Invalid QR code format', isError: true);
    }
  }

  void _toggleScanner() {
    if (_scannerActive) {
      _scannerController?.stop();
      setState(() => _scannerActive = false);
    } else {
      _scannerController = MobileScannerController();
      setState(() => _scannerActive = true);
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
        title: const Text('Mark Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: SyncManager().pendingCount,
            builder: (ctx, count, _) {
              if (count <= 0) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => Navigator.push(context, buildCupertinoRoute(const SyncStatusScreen())),
                  child: AppBadge(label: '$count pending', color: c.accentOrange),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Info Card
            AppCard(
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // QR Scanner Section
            const SectionTitle(title: 'Scan QR Code', icon: Icons.qr_code_scanner, centered: true),
            const SizedBox(height: 14),
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
                      'Point camera at the QR code displayed by your teacher',
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
                    const Icon(Icons.camera_alt, size: 48, color: Colors.amber),
                    const SizedBox(height: 12),
                    Text(
                      'Scan the QR code projected by your teacher',
                      style: TextStyle(color: c.muted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Open Camera',
                      icon: Icons.qr_code_scanner,
                      onPressed: _toggleScanner,
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0, duration: 400.ms),
            const SizedBox(height: 24),

            // Smart Auto-Detect
            const SectionTitle(title: 'Smart Attendance', icon: Icons.bluetooth, centered: true),
            const SizedBox(height: 14),
            AppCard(
              borderColor: c.accent.withValues(alpha: 0.2),
              child: Column(
                children: [
                  Icon(Icons.bluetooth_searching, size: 36, color: c.accent),
                  const SizedBox(height: 12),
                  Text(
                    'Automatically detect nearby class sessions',
                    style: TextStyle(color: c.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Start Smart Scan',
                    icon: Icons.bluetooth,
                    onPressed: () => Navigator.push(
                      context,
                      buildCupertinoRoute(StudentBleListenerScreen(profile: widget.profile)),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 50.ms).slideY(begin: 0.08, end: 0, duration: 400.ms, delay: 50.ms),
            const SizedBox(height: 24),

            // Manual Token Entry
            const SectionTitle(title: 'Or Enter Token Manually', icon: Icons.keyboard, centered: true),
            const SizedBox(height: 14),
            AppCard(
              borderColor: c.accentOrange.withValues(alpha: 0.2),
              child: Column(
                children: [
                  const Icon(Icons.edit, size: 36, color: Colors.amber),
                  const SizedBox(height: 12),
                  Text(
                    'Type the 6-character code shown on screen',
                    style: TextStyle(color: c.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tokenCtrl,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: c.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'ABC123',
                      hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.4)),
                      counterText: '',
                      filled: true,
                      fillColor: c.bg3,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: c.accent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Submit Token',
                    icon: Icons.send,
                    loading: _submitting,
                    onPressed: _submitting ? null : () => _submitAttendance(_tokenCtrl.text, 'manual'),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.08, end: 0, duration: 400.ms, delay: 100.ms),
            const SizedBox(height: 16),

            // View History Button
            Center(
              child: GhostButton(
                label: 'View Attendance History',
                icon: Icons.history,
                color: c.accent,
                onPressed: () => Navigator.push(
                  context,
                  buildCupertinoRoute(StudentAttendanceHistoryScreen(profile: widget.profile)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
