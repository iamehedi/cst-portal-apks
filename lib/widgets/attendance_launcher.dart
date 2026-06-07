import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../screens/attendance_session_screen.dart';
import '../services/attendance_service.dart';
import '../services/routine_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../utils/page_transitions.dart';
import 'common.dart';
import 'theme_picker.dart';

/// Shared attendance launcher widget used by both Teacher and Admin dashboards.
class AttendanceLauncher extends StatefulWidget {
  final Map<String, dynamic> profile;
  const AttendanceLauncher({super.key, required this.profile});

  @override
  State<AttendanceLauncher> createState() => _AttendanceLauncherState();
}

class _AttendanceLauncherState extends State<AttendanceLauncher> {
  String _department = 'CST';
  String? _subject;
  int _semester = 3;
  List<Map<String, dynamic>> _allRoutineSlots = [];
  List<Map<String, dynamic>> _todaySlots = [];
  bool _loadingSubjects = true;
  Map<String, dynamic>? _activeSession;
  bool _checkingSession = true;
  int _sessionCheckGeneration = 0;

  // Date & time
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  static const _departments = ['CST'];
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
    // 135-minute (2h 15m) combined periods
    '1:30 – 3:45 PM (2h 15m)',
    '2:15 – 4:30 PM (2h 15m)',
    '3:00 – 5:15 PM (2h 15m)',
    '3:45 – 6:00 PM (2h 15m)',
    '4:30 – 6:45 PM (2h 15m)',
  ];
  // Start times for each period (used to auto-set the time picker)
  static const _periodStartTimes = [
    TimeOfDay(hour: 13, minute: 30),
    TimeOfDay(hour: 14, minute: 15),
    TimeOfDay(hour: 15, minute: 0),
    TimeOfDay(hour: 15, minute: 45),
    TimeOfDay(hour: 16, minute: 30),
    TimeOfDay(hour: 17, minute: 15),
    TimeOfDay(hour: 18, minute: 0),
    // 135-minute combined period start times (same as first period of the block)
    TimeOfDay(hour: 13, minute: 30),
    TimeOfDay(hour: 14, minute: 15),
    TimeOfDay(hour: 15, minute: 0),
    TimeOfDay(hour: 15, minute: 45),
    TimeOfDay(hour: 16, minute: 30),
  ];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    _checkActiveSession();
  }

  Future<void> _loadSubjects() async {
    setState(() => _loadingSubjects = true);
    try {
      final routines = await RoutineService.fetch(_semester);
      if (!mounted) return;
      setState(() {
        _allRoutineSlots = routines.map((slot) => slot.toRow()).toList();
        _filterSlotsForDate();
        _loadingSubjects = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  void _filterSlotsForDate() {
    final dayCode = _dayMap[_selectedDate.weekday] ?? '';
    _todaySlots = _allRoutineSlots
        .where((r) => RoutineService.normalizeDay(r['day']?.toString()) == dayCode)
        .toList();
    // Auto-select first subject and its time if current selection not in today's list
    final todaySubjects = _todaySlots.map((r) => r['subject']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    if (todaySubjects.isEmpty) {
      _subject = null;
    } else if (!todaySubjects.contains(_subject)) {
      _subject = todaySubjects.first;
      // Auto-set time to the first slot's period start time
      final pIdx = int.tryParse(_todaySlots.first['period_index']?.toString() ?? '') ?? 0;
      if (pIdx < _periodStartTimes.length) {
        _selectedTime = _periodStartTimes[pIdx];
      }
    }
  }

  Future<void> _checkActiveSession() async {
    final gen = ++_sessionCheckGeneration;
    try {
      final userId = SupabaseService.currentUser?.id;
      if (userId == null) {
        if (mounted && gen == _sessionCheckGeneration) setState(() => _checkingSession = false);
        return;
      }
      final session = await AttendanceService.getActiveSession(userId);
      if (mounted && gen == _sessionCheckGeneration) {
        setState(() { _activeSession = session; _checkingSession = false; });
      }
    } catch (_) {
      if (mounted && gen == _sessionCheckGeneration) setState(() => _checkingSession = false);
    }
  }

  void _startSession() {
    if (_subject == null || _subject!.isEmpty) {
      showAppSnackbar(context, 'Please select a subject', isError: true);
      return;
    }
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    Navigator.push(
      context,
      buildCupertinoRoute(AttendanceSessionScreen(
        department: _department,
        subject: _subject!,
        semester: _semester,
        profile: widget.profile,
        classDate: dateStr,
        classTime: timeStr,
      )),
    ).then((_) {
      if (mounted) _checkActiveSession();
    });
  }

  Future<void> _resumeSession() async {
    if (_activeSession == null) return;
    Navigator.push(
      context,
      buildCupertinoRoute(AttendanceSessionScreen(
        department: _activeSession!['department'] ?? 'CST',
        subject: _activeSession!['subject'] ?? '',
        semester: _activeSession!['semester'] ?? 1,
        profile: widget.profile,
        existingSessionId: _activeSession!['id']?.toString(),
      )),
    ).then((_) {
      if (mounted) _checkActiveSession();
    });
  }

  Future<void> _endActiveSession() async {
    if (_activeSession == null) return;
    try {
      await AttendanceService.endSession(_activeSession!['id']?.toString() ?? '');
      if (mounted) {
        setState(() => _activeSession = null);
        showAppSnackbar(context, 'Session ended');
        _checkActiveSession();
      }
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text('Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          IconButton(
            icon: Icon(Icons.palette_outlined, color: c.accent),
            tooltip: 'Theme',
            onPressed: () => showThemePicker(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context) + 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active Session Card
            if (_checkingSession)
              const AppCard(child: ShimmerBox(height: 80))
            else if (_activeSession != null) ...[
              AppCard(
                borderColor: c.accent3.withValues(alpha: 0.3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: c.accent3, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Active Session',
                          style: TextStyle(
                            color: c.accent3,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _activeSession!['subject'] ?? '',
                      style: TextStyle(color: c.white, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${SupabaseService.semesterFromInt(_activeSession!['semester'])} Semester · ${_activeSession!['department'] ?? 'CST'}',
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                    if (_activeSession!['class_date'] != null || _activeSession!['class_time'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (_activeSession!['class_date'] != null) _activeSession!['class_date'],
                            if (_activeSession!['class_time'] != null) _activeSession!['class_time'],
                          ].join(' · '),
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Resume',
                            icon: Icons.play_arrow,
                            onPressed: _resumeSession,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GhostButton(
                            label: 'End Session',
                            icon: Icons.stop,
                            color: c.danger,
                            onPressed: _endActiveSession,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // New Session Form
            if (_activeSession == null && !_checkingSession) ...[
              const SectionTitle(title: 'Start New Session', icon: Icons.qr_code, centered: true),
              const SizedBox(height: 16),
              AppCard(
                borderColor: c.accent.withValues(alpha: 0.2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DEPARTMENT', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _buildDropdown(c, _department, _departments, (v) {
                      if (v != null) setState(() => _department = v);
                    }),
                    // Semester picker removed (defaults to 3rd semester)
                    const SizedBox(height: 16),

                    Text('SUBJECT', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_loadingSubjects)
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
                          'No classes scheduled for ${_dayMap[_selectedDate.weekday] ?? ''}',
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
                        final isSelected = _subject == subj;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _subject = subj);
                            // Auto-set class time to the period's start time
                            if (pIdx < _periodStartTimes.length) {
                              setState(() => _selectedTime = _periodStartTimes[pIdx]);
                            }
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
                    const SizedBox(height: 16),

                    // Date & Time row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('DATE', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                    lastDate: DateTime.now().add(const Duration(days: 7)),
                                    builder: (ctx, child) => Theme(data: buildDatePickerTheme(ctx, Theme.of(ctx)), child: child!),
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedDate = picked);
                                    _filterSlotsForDate();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 16, color: c.accent),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                        style: TextStyle(color: c.white, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CLASS TIME', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedTime,
                                    builder: (ctx, child) => Theme(data: buildDatePickerTheme(ctx, Theme.of(ctx)), child: child!),
                                  );
                                  if (picked != null) setState(() => _selectedTime = picked);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.access_time, size: 16, color: c.accent),
                                      const SizedBox(width: 8),
                                      Text(
                                        _selectedTime.format(context),
                                        style: TextStyle(color: c.white, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    PrimaryButton(
                      label: 'Start Session',
                      icon: Icons.qr_code_2,
                      onPressed: _startSession,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(ThemeColors c, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.bg3,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.firstOrNull,
          dropdownColor: c.bg2,
          style: TextStyle(color: c.text, fontSize: 14),
          isExpanded: true,
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
