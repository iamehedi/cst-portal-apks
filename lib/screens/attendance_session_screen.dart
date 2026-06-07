import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/attendance_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';

class AttendanceSessionScreen extends StatefulWidget {
  final String department;
  final String subject;
  final int semester;
  final Map<String, dynamic> profile;
  final String? existingSessionId;
  final String? classDate;
  final String? classTime;

  const AttendanceSessionScreen({
    super.key,
    required this.department,
    required this.subject,
    required this.semester,
    required this.profile,
    this.existingSessionId,
    this.classDate,
    this.classTime,
  });

  @override
  State<AttendanceSessionScreen> createState() => _AttendanceSessionScreenState();
}

class _AttendanceSessionScreenState extends State<AttendanceSessionScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  String? _sessionId;
  String _currentToken = '';
  int _secondsRemaining = 30;
  List<Map<String, dynamic>> _attendees = [];
  bool _initializing = true;
  String? _error;
  bool _manualExpanded = false;
  bool _submittingManual = false;
  final _manualIdCtrl = TextEditingController();
  final _manualNameCtrl = TextEditingController();

  // Single timer — lives for the entire session, ticks every second
  Timer? _ticker;
  // Stream subscription for live attendees
  StreamSubscription<List<Map<String, dynamic>>>? _attendanceSub;
  // Guard: is a token rotation currently in-flight?
  bool _rotating = false;
  // Guard: is a stream retry currently scheduled?
  bool _retryingStream = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _attendanceSub?.cancel();
    _manualIdCtrl.dispose();
    _manualNameCtrl.dispose();
    super.dispose();
  }

  // ── Session Init ─────────────────────────────────────────────────────────
  Future<void> _initSession() async {
    try {
      if (widget.existingSessionId != null) {
        // Resume existing session
        final session = await AttendanceService.getSession(widget.existingSessionId!)
            .timeout(const Duration(seconds: 10), onTimeout: () => null);
        if (session == null) throw Exception('Session not found or has ended');
        _sessionId = session['id']?.toString();

        // Use existing token if still fresh
        final existingToken = session['current_token']?.toString();
        final tokenCreatedAt = session['token_created_at'] != null
            ? DateTime.tryParse(session['token_created_at'].toString())
            : null;
        final tokenAge = tokenCreatedAt != null
            ? DateTime.now().difference(tokenCreatedAt.toLocal()).inSeconds
            : 999;

        if (existingToken != null && existingToken.isNotEmpty && tokenAge < 30) {
          _currentToken = existingToken;
          _secondsRemaining = 30 - tokenAge;
        } else {
          await _rotateToken();
        }
      } else {
        // Create new session
        final session = await AttendanceService.createSession(
          department: widget.department,
          subject: widget.subject,
          semester: widget.semester,
          classDate: widget.classDate,
          classTime: widget.classTime,
        ).timeout(const Duration(seconds: 10));
        _sessionId = session['id']?.toString();
        if (_sessionId == null) throw Exception('Session creation failed: no ID returned');
        await _rotateToken();
      }

      // Start the single ticker — runs every second for the session lifetime
      _startTicker();
      _subscribeToAttendance();
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      _cleanup();
      if (mounted) setState(() { _error = friendlyError(e); _initializing = false; });
    }
  }

  // ── Single Ticker ────────────────────────────────────────────────────────
  // One timer, created once, ticks every second. Handles countdown + rotation.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _ticker?.cancel(); return; }
      if (_secondsRemaining <= 0) {
        // Already at zero — trigger rotation if not already in-flight
        if (!_rotating) _rotateToken();
        return; // Don't decrement below zero
      }
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0 && !_rotating) {
        _rotateToken();
      }
    });
  }

  // ── Token Rotation ───────────────────────────────────────────────────────
  // Only updates DB + local state. Does NOT touch the timer.
  Future<void> _rotateToken() async {
    if (_sessionId == null || !mounted || _rotating) return;
    _rotating = true;
    final token = _generateToken();
    try {
      await AttendanceService.rotateToken(_sessionId!, token)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // DB update failed or timed out — token only updated locally
    }
    if (!mounted) { _rotating = false; return; }
    setState(() {
      _currentToken = token;
      _secondsRemaining = 30;
    });
    _rotating = false;
  }

  String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Attendance Stream ────────────────────────────────────────────────────
  void _subscribeToAttendance() {
    if (_sessionId == null) return;
    _attendanceSub?.cancel();
    _retryingStream = false;
    _attendanceSub = AttendanceService.getAttendanceStream(_sessionId!).listen(
      (data) {
        if (mounted) setState(() => _attendees = data);
      },
      onError: (_) {
        if (!mounted || _retryingStream) return;
        _retryingStream = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _sessionId != null) _subscribeToAttendance();
        });
      },
    );
  }

  // ── End Session ──────────────────────────────────────────────────────────
  Future<void> _endSession() async {
    if (_sessionId == null) { if (mounted) Navigator.pop(context); return; }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.bg2,
        title: Text('End Session?', style: TextStyle(color: context.colors.white)),
        content: Text(
          'Students will no longer be able to mark attendance.',
          style: TextStyle(color: context.colors.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: context.colors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('End Session', style: TextStyle(color: context.colors.danger))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    _cleanup();
    try {
      final ended = await AttendanceService.endSession(_sessionId!);
      if (!ended) {
        // Session wasn't found in DB — already ended or deleted
        if (mounted) showAppSnackbar(context, 'Session was already ended');
      } else if (mounted) {
        showAppSnackbar(context, 'Session ended');
      }
    } catch (e) {
      if (mounted) showAppSnackbar(context, 'Failed to end session: ${friendlyError(e)}', isError: true);
    }
    if (mounted) Navigator.pop(context);
  }

  // ── Manual Entry ─────────────────────────────────────────────────────────
  Future<void> _submitManual() async {
    final id = _manualIdCtrl.text.trim();
    final name = _manualNameCtrl.text.trim();
    if (id.isEmpty || name.isEmpty) {
      showAppSnackbar(context, 'Please enter both Student ID and Name', isError: true);
      return;
    }
    setState(() => _submittingManual = true);
    try {
      final result = await AttendanceService.validateAndMarkAttendance(
        sessionId: _sessionId,
        token: _currentToken,
        studentId: id,
        studentName: name,
        method: 'manual',
      );
      if (!mounted) return;
      if (result['success'] == true) {
        _manualIdCtrl.clear();
        _manualNameCtrl.clear();
        setState(() => _manualExpanded = false);
        _showManualSuccessDialog(name, id);
      } else {
        _showManualErrorDialog(result['error']?.toString() ?? 'Failed to mark attendance');
      }
    } catch (e) {
      if (mounted) _showManualErrorDialog(friendlyError(e));
    }
    if (mounted) setState(() => _submittingManual = false);
  }

  void _showManualSuccessDialog(String name, String id) {
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
              Text(
                'Attendance Marked!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white),
              ),
              const SizedBox(height: 16),
              _infoRow(c, 'Student ID', id),
              _infoRow(c, 'Name', name),
              _infoRow(c, 'Time', _formatNow()),
              _infoRow(c, 'Method', 'Manual'),
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

  void _showManualErrorDialog(String error) {
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
                'Failed to Mark',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.white),
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

  // ── Cleanup ──────────────────────────────────────────────────────────────
  void _cleanup() {
    _ticker?.cancel();
    _ticker = null;
    _attendanceSub?.cancel();
    _attendanceSub = null;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_initializing) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: c.accent),
              const SizedBox(height: 16),
              Text(
                widget.existingSessionId != null ? 'Resuming session...' : 'Starting session...',
                style: TextStyle(color: c.muted),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, foregroundColor: c.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 48, color: Colors.amber),
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: c.danger), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Retry', onPressed: () {
                  setState(() { _initializing = true; _error = null; });
                  _initSession();
                }),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.white,
        title: Text(
          '${widget.subject} — ${SupabaseService.semesterFromInt(widget.semester)} Semester',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton.icon(
            onPressed: _endSession,
            icon: Icon(Icons.stop_circle_outlined, color: c.danger, size: 18),
            label: Text('End', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.screenPadding(context),
            vertical: 24,
          ),
          child: Column(
            children: [
              Center(child: _buildQrCard(c)),
              const SizedBox(height: 24),
              _buildLiveSection(c),
              const SizedBox(height: 20),
              _buildManualSection(c),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── QR Card ──────────────────────────────────────────────────────────────
  Widget _buildQrCard(ThemeColors c) {
    final progress = (_secondsRemaining / 30.0).clamp(0.0, 1.0);
    final qrData = _sessionId != null ? '$_sessionId|$_currentToken' : _currentToken;

    return AppCard(
      borderColor: c.accent.withValues(alpha: 0.3),
      child: Column(
        children: [
          Text(
            'SESSION TOKEN',
            style: TextStyle(
              color: c.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _currentToken,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: c.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    backgroundColor: c.bg3,
                    color: _secondsRemaining <= 5 ? c.danger : c.accent,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$_secondsRemaining',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _secondsRemaining <= 5 ? c.danger : c.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Token refreshes every 30 seconds',
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack);
  }

  // ── Live Attendance ──────────────────────────────────────────────────────
  Widget _buildLiveSection(ThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                title: 'Live Attendance',
                trailing: AppBadge(
                  label: '${_attendees.length} checked in',
                  color: c.accent3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_attendees.isEmpty)
          AppCard(
            borderColor: c.border,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_empty, size: 32, color: Colors.amber),
                    const SizedBox(height: 8),
                    Text('Waiting for students...', style: TextStyle(color: c.muted, fontSize: 13)),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _attendees.length,
            itemBuilder: (ctx, i) {
              final a = _attendees[i];
              final isQr = a['method'] == 'qr';
              final time = a['marked_at'] != null
                  ? DateFormat('hh:mm:ss a').format(DateTime.parse(a['marked_at']).toLocal())
                  : '';

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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (isQr ? c.accent3 : c.accentOrange).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(isQr ? Icons.phone_android : Icons.edit, size: 16, color: isQr ? c.accent3 : c.accentOrange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['student_name'] ?? '',
                            style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            'ID: ${a['student_id'] ?? ''}',
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppBadge(
                          label: isQr ? 'QR' : 'MANUAL',
                          color: isQr ? c.accent3 : c.accentOrange,
                        ),
                        const SizedBox(height: 4),
                        Text(time, style: TextStyle(color: c.muted, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ).animate(delay: Duration(milliseconds: (i * 50).clamp(0, 400)))
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: 0.1, end: 0, duration: 300.ms);
            },
          ),
      ],
    );
  }

  // ── Manual Entry ─────────────────────────────────────────────────────────
  Widget _buildManualSection(ThemeColors c) {
    return AppCard(
      borderColor: c.accentOrange.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _manualExpanded = !_manualExpanded),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: c.accentOrange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(                      'Manual Entry',
                      style: TextStyle(
                        color: c.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                  ),
                ),
                Icon(
                  _manualExpanded ? Icons.expand_less : Icons.expand_more,
                  color: c.muted,
                ),
              ],
            ),
          ),
          if (_manualExpanded) ...[
            const SizedBox(height: 16),
            AppTextField(
              label: 'Student ID',
              hint: 'Roll or Registration number',
              controller: _manualIdCtrl,
              prefixIcon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Student Name',
              hint: 'Full name',
              controller: _manualNameCtrl,
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Mark Attendance',
              icon: Icons.check,
              loading: _submittingManual,
              onPressed: _submitManual,
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }
}
