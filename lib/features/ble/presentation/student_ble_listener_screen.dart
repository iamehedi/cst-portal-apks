import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../utils/theme_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/common.dart';
import '../providers/ble_attendance_provider.dart';

class StudentBleListenerScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentBleListenerScreen({super.key, required this.profile});

  @override
  State<StudentBleListenerScreen> createState() => _StudentBleListenerScreenState();
}

class _StudentBleListenerScreenState extends State<StudentBleListenerScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<BleAttendanceProvider>();
    // Reset any lingering state from a previous BLE session so the student
    // starts fresh every time they enter this screen (e.g. after switching subjects).
    provider.reset();
    final studentId = (widget.profile['roll'] ?? '').toString();
    final studentName = (widget.profile['name'] ?? 'Student').toString();
    provider.setIdentity(studentId, studentName);

    // Listen for approval/rejection state to show a popup dialog
    provider.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    final provider = context.read<BleAttendanceProvider>();
    // Reset dialog guard when returning to idle (new scan cycle)
    if (provider.scanState == 'idle') {
      _dialogShown = false;
      return;
    }
    if (provider.scanState == 'approved' && !_dialogShown) {
      _dialogShown = true;
      _showResultDialog('Present ✅', Colors.green, Icons.check_circle);
    } else if (provider.scanState == 'rejected' && !_dialogShown) {
      _dialogShown = true;
      _showResultDialog('Rejected ❌', context.colorsOf.danger, Icons.cancel);
    }
  }

  void _showResultDialog(String message, Color color, IconData icon) {
    final c = context.colorsOf;
    final subject = context.read<BleAttendanceProvider>().detectedSubject ?? '';
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
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
              ),
              if (subject.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subject,
                  style: TextStyle(color: c.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Your attendance has been recorded locally.',
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
      ).animate().scale(begin: const Offset(0.8, 0.8), duration: 350.ms, curve: Curves.easeOutBack).fadeIn(duration: 250.ms),
    );
  }

  @override
  void dispose() {
    context.read<BleAttendanceProvider>().removeListener(_onStateChanged);
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
                Text('Please use an Android device to scan for Smart attendance sessions.',
                    style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final provider = context.watch<BleAttendanceProvider>();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: const Text('Smart Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (provider.scanState == 'scanning' || provider.scanState == 'found' ||
              provider.scanState == 'connecting' || provider.scanState == 'pending')
            TextButton(
              onPressed: () {
                provider.stopScanning();
                if (provider.scanState == 'connecting' || provider.scanState == 'found' ||
                    provider.scanState == 'pending') {
                  provider.disconnect();
                }
              },
              child: Text('Cancel', style: TextStyle(color: c.muted)),
            ),
        ],
      ),
      body: _buildBody(c, provider),
    );
  }

  Widget _buildBody(ThemeColors c, BleAttendanceProvider provider) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(Responsive.screenPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(c, provider),
          const SizedBox(height: 24),

          if (provider.scanState == 'idle')
            _buildStartScanning(c, provider)
          else if (provider.scanState == 'scanning')
            _buildScanning(c)
          else if (provider.scanState == 'found')
            _buildFound(c, provider)
          else if (provider.scanState == 'connecting')
            _buildConnecting(c)
          else if (provider.scanState == 'pending')
            _buildPending(c, provider)
          else if (provider.scanState == 'approved')
            _buildIdleFallback(c, 'Present ✅', Colors.green)
          else if (provider.scanState == 'rejected')
            _buildIdleFallback(c, 'Rejected ❌', c.danger)
          else if (provider.scanState == 'error')
            _buildError(c, provider.statusMessage ?? 'An error occurred'),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeColors c, BleAttendanceProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.accent.withValues(alpha: 0.1), c.accent.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(provider.statusMessage ?? 'Tap scan to begin',
              style: TextStyle(color: c.white, fontSize: 16, fontWeight: FontWeight.w700)),
          if (provider.detectedSubject != null) ...[
            const SizedBox(height: 4),
            Text(provider.detectedSubject!, style: TextStyle(color: c.accent, fontSize: 13)),
          ],
          if (provider.detectedRssi != null) ...[
            const SizedBox(height: 4),
            Text('Signal: ${provider.detectedRssi} dBm', style: TextStyle(color: c.muted, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildStartScanning(ThemeColors c, BleAttendanceProvider provider) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          if (!mounted) return;
          final granted = await provider.requestBlePermission();
          if (!mounted) return;
          if (!granted) {
            showAppSnackbar(context, 'BLE permission denied', isError: true);
            return;
          }
          provider.startScanning();
        },
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Start Scanning'),
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildScanning(ThemeColors c) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.bluetooth_searching, size: 64, color: c.accent),
          const SizedBox(height: 16),
          Text('Searching for class...', style: TextStyle(color: c.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Make sure Bluetooth is on', style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildFound(ThemeColors c, BleAttendanceProvider provider) {
    final isSubmitted = provider.statusMessage?.contains('Check-in') == true;
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: isSubmitted ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(isSubmitted ? Icons.check_circle : Icons.check_circle,
                color: Colors.green, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            isSubmitted ? 'Check-in Submitted!' : 'Class Found!',
            style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(provider.detectedSubject ?? '',
              style: TextStyle(color: c.white, fontSize: 15)),
          const SizedBox(height: 4),
          Text(provider.statusMessage ?? '',
              style: TextStyle(color: c.muted, fontSize: 11)),
          if (!isSubmitted) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 8),
            Text('Sending check-in...', style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildConnecting(ThemeColors c) {
    return const Center(
      child: Column(
        children: [
          SizedBox(height: 40),
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting...'),
        ],
      ),
    );
  }

  Widget _buildPending(ThemeColors c, BleAttendanceProvider provider) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.hourglass_empty, color: Colors.orange, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Waiting for Approval',
            style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(provider.detectedSubject ?? '',
              style: TextStyle(color: c.white, fontSize: 15)),
          const SizedBox(height: 8),
          Text(
            'The teacher will review your check-in request.',
            style: TextStyle(color: c.muted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.orange),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  /// Minimal fallback shown after the dialog is dismissed, before auto-reset.
  Widget _buildIdleFallback(ThemeColors c, String message, Color color) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(message.contains('✅') ? Icons.check_circle : Icons.cancel, color: color, size: 48),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Returning to scan...', style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildError(ThemeColors c, String message) {
    final provider = context.read<BleAttendanceProvider>();
    final isBtOff = message.toLowerCase().contains('bluetooth');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(isBtOff ? Icons.bluetooth_disabled : Icons.error_outline, color: c.danger, size: 48),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: c.danger, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: isBtOff
                ? () => provider.retryScan()
                : () => provider.disconnect(),
            child: Text(isBtOff ? 'Re-enable & Retry' : 'Try Again'),
          ),
        ],
      ),
    );
  }
}
