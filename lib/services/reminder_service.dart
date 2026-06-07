import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'routine_service.dart';

/// Manages local notification reminders for class times and exam times.
/// Reminder preferences are stored in SharedPreferences so they persist.
class ReminderService {
  static const _classRemindersKey = 'class_reminders_enabled';
  static const _examRemindersKey = 'exam_reminders_enabled';
  static const _classMinutesKey = 'class_reminder_minutes';
  static const _defaultClassMinutes = 15;
  static const _examHoursBefore = 24; // Notify 24 hours before exam

  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  // ── Preference Getters/Setters ──────────────────────────────────

  /// Whether class reminders are enabled.
  static Future<bool> areClassRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_classRemindersKey) ?? false;
  }

  /// Set class reminders preference.
  static Future<void> setClassRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_classRemindersKey, enabled);
  }

  /// Get class reminder minutes before class.
  static Future<int> getClassReminderMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_classMinutesKey) ?? _defaultClassMinutes;
  }

  /// Set class reminder minutes before class.
  static Future<void> setClassReminderMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_classMinutesKey, minutes);
  }

  /// Whether exam reminders are enabled.
  static Future<bool> areExamRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_examRemindersKey) ?? false;
  }

  /// Set exam reminders preference.
  static Future<void> setExamRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_examRemindersKey, enabled);
  }

  // ── Scheduling ──────────────────────────────────────────────────

  /// Schedule all class reminders from the routine data.
  /// [routine] is a list of routine slot maps containing
  /// day, period_index, subject, subject_code, teacher, room, semester.
  static Future<void> scheduleClassReminders(
    List<Map<String, dynamic>> routine,
  ) async {
    final enabled = await areClassRemindersEnabled();
    if (!enabled) return;

    // Cancel any previously scheduled class reminders first
    await _cancelClassReminders();

    final notif = NotificationService();
    int id = 2000; // Base ID for class reminders

    final minutesBefore = await getClassReminderMinutes();

    // Fetch off days once to avoid DB calls in every iteration
    final offDays = await SupabaseService.getOffDays();

    for (final cls in routine) {
      final day = cls['day']?.toString().toUpperCase() ?? '';
      final periodIndex = int.tryParse(cls['period_index']?.toString() ?? '') ?? 0;
      final subject = cls['subject']?.toString() ?? 'Class';
      final room = cls['room']?.toString() ?? '';

      final scheduledDate = _nextDayOfWeek(day, periodIndex);
      if (scheduledDate == null) continue;

      // Skip if this class falls on an off day (college closed)
      if (_isDateInOffDays(scheduledDate, offDays)) continue;

      // Subtract the reminder lead time
      final reminderTime = scheduledDate.subtract(
        Duration(minutes: minutesBefore),
      );

      if (reminderTime.isAfter(DateTime.now())) {
        final body = room.isNotEmpty
            ? '$subject in Room $room starts in $minutesBefore min'
            : '$subject class starts in $minutesBefore min';
        await notif.scheduleNotification(id++, '📚 Class Reminder', body, reminderTime, repeatWeekly: true);
      }
    }
  }

  /// Schedule all exam reminders.
  static Future<void> scheduleExamReminders(
    List<Map<String, dynamic>> exams,
  ) async {
    final enabled = await areExamRemindersEnabled();
    if (!enabled) return;

    await _cancelExamReminders();

    final notif = NotificationService();
    int id = 3000; // Base ID for exam reminders

    for (final exam in exams) {
      final examDate = exam['exam_date']?.toString();
      final startTime = exam['start_time']?.toString();
      final subject = exam['subject']?.toString() ?? 'Exam';
      final room = exam['room']?.toString() ?? '';
      final examType = exam['exam_type']?.toString() ?? '';

      if (examDate == null || startTime == null) continue;

      try {
        // Parse exam date and start time
        final date = DateTime.parse(examDate);
        final timeParts = startTime.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1].substring(0, 2));
        final examDateTime = DateTime(date.year, date.month, date.day, hour, minute);

        final reminderTime = examDateTime.subtract(
          const Duration(hours: _examHoursBefore),
        );

        if (reminderTime.isAfter(DateTime.now())) {
          final dateStr = DateFormat('MMM d').format(date);
          final body = room.isNotEmpty
              ? '$examType · $subject in Room $room · $dateStr'
              : '$examType · $subject · $dateStr';
          await notif.scheduleNotification(
            id++,
            '📝 Exam Reminder',
            body,
            reminderTime,
            repeatWeekly: false,
          );
        }
      } catch (_) {
        // Skip if date parsing fails
      }
    }
  }

  // ── Cancellation ────────────────────────────────────────────────

  /// Cancel all scheduled class reminders.
  static Future<void> cancelClassReminders() async {
    await _cancelClassReminders();
  }

  /// Cancel all scheduled exam reminders.
  static Future<void> cancelExamReminders() async {
    await _cancelExamReminders();
  }

  // ── Auto-reschedule on app launch ─────────────────────────────

  /// Re-schedules all enabled reminders on app start.
  /// Call this after profile loads to recover from device reboots
  /// or OS alarm clears.
  static Future<void> rescheduleOnAppLaunch() async {
    try {
      final classEnabled = await areClassRemindersEnabled();
      final examEnabled = await areExamRemindersEnabled();

      if (classEnabled) {
        // Get user's semester to fetch their routine
        final user = SupabaseService.currentUser;
        if (user != null) {
          final profile = await SupabaseService.getProfile(user.id);
          final semester = RoutineService.profileSemester(profile);
          if (semester >= 1) {
            final routine = await RoutineService.fetch(semester);
            await scheduleClassReminders(
              routine.map((slot) => slot.toReminderMap()).toList(),
            );
          }
        }
      }

      if (examEnabled) {
        final user = SupabaseService.currentUser;
        if (user != null) {
          final profile = await SupabaseService.getProfile(user.id);
          final semester = int.tryParse(profile?['semester']?.toString() ?? '');
          if (semester != null) {
            final exams = await SupabaseService.getExams(semester: semester);
            await scheduleExamReminders(exams);
          }
        }
      }
    } catch (e) {
      debugPrint('[Reminder] Auto-reschedule on launch failed: $e');
    }
  }

  static Future<void> _cancelClassReminders() async {
    final notif = NotificationService();
    for (int id = 2000; id < 2100; id++) {
      await notif.cancelNotification(id);
    }
  }

  static Future<void> _cancelExamReminders() async {
    final notif = NotificationService();
    for (int id = 3000; id < 3100; id++) {
      await notif.cancelNotification(id);
    }
  }

  /// Check if a [date] falls within any off-day range from the list.
  static bool _isDateInOffDays(DateTime date, List<Map<String, dynamic>> offDays) {
    final dateStr = date.toIso8601String().substring(0, 10);
    for (final day in offDays) {
      final start = day['start_date']?.toString() ?? '';
      final end = day['end_date']?.toString() ?? '';
      if (start.compareTo(dateStr) <= 0 && dateStr.compareTo(end) <= 0) return true;
    }
    return false;
  }

  // ── Helpers ──────────────────────────────────────────────────────

  // Dart DateTime.weekday: Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6, Sun=7
  static const _dayIndex = {
    'MON': 1,
    'TUE': 2,
    'WED': 3,
    'THU': 4,
    'FRI': 5,
    'SAT': 6,
    'SUN': 7,
  };

  /// Get the next [DateTime] for the given weekday abbreviation and period index.
  static DateTime? _nextDayOfWeek(String day, int periodIndex) {
    final targetWeekday = _dayIndex[day];
    if (targetWeekday == null) return null;

    final now = DateTime.now();
    final currentWeekday = now.weekday;

    int daysUntilTarget = targetWeekday - currentWeekday;
    if (daysUntilTarget <= 0) {
      daysUntilTarget += 7; // Next week
    }

    // Parse period time using the same schedule as routine_screen.dart
    final periodTime = _periodStartTime(periodIndex);
    if (periodTime == null) return null;

    final nextDate = DateTime(
      now.year,
      now.month,
      now.day + daysUntilTarget,
      periodTime.hour,
      periodTime.minute,
    );

    return nextDate;
  }

  /// Returns the start time of a period given its index.
  static final List<TimeOfDay> _periodStarts = [
    const TimeOfDay(hour: 8, minute: 0),
    const TimeOfDay(hour: 8, minute: 50),
    const TimeOfDay(hour: 9, minute: 40),
    const TimeOfDay(hour: 10, minute: 40),
    const TimeOfDay(hour: 11, minute: 30),
    const TimeOfDay(hour: 12, minute: 20),
    const TimeOfDay(hour: 14, minute: 0),
  ];

  static TimeOfDay? _periodStartTime(int index) {
    if (index < 0 || index >= _periodStarts.length) return null;
    return _periodStarts[index];
  }
}
