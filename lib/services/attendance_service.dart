import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AttendanceService {
  static SupabaseClient get _client => SupabaseService.client;

  // ─── Session CRUD ──────────────────────────────────────────────────────────

  /// Create a new attendance session. Returns the created record (including id).
  static Future<Map<String, dynamic>> createSession({
    required String department,
    required String subject,
    required int semester,
    String? classDate,
    String? classTime,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final data = {
      'teacher_id': userId,
      'department': department,
      'subject': subject,
      'semester': semester,
      'is_active': true,
      if (classDate != null) 'class_date': classDate,
      if (classTime != null) 'class_time': classTime,
    };

    final res = await _client
        .from('attendance_sessions')
        .insert(data)
        .select()
        .single();
    return res;
  }

  /// End an active session. Returns true if the update succeeded.
  static Future<bool> endSession(String sessionId) async {
    try {
      await _client
          .from('attendance_sessions')
          .update({'is_active': false})
          .eq('id', sessionId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Rotate the token for an active session.
  static Future<void> rotateToken(String sessionId, String newToken) async {
    await _client.from('attendance_sessions').update({
      'current_token': newToken,
      'token_created_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', sessionId);
  }

  /// Get the teacher's currently active session (if any).
  static Future<Map<String, dynamic>?> getActiveSession(String teacherId) async {
    final res = await _client
        .from('attendance_sessions')
        .select()
        .eq('teacher_id', teacherId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res;
  }

  /// Get a single active session by ID. Returns null if not found or already ended.
  static Future<Map<String, dynamic>?> getSession(String sessionId) async {
    final res = await _client
        .from('attendance_sessions')
        .select()
        .eq('id', sessionId)
        .eq('is_active', true)
        .maybeSingle();
    return res;
  }

  // ─── Attendance Records ────────────────────────────────────────────────────

  /// Real-time stream of attendance records for a session.
  static Stream<List<Map<String, dynamic>>> getAttendanceStream(String sessionId) {
    return _client
        .from('attendance_records')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('marked_at', ascending: false);
  }

  /// Validate token and mark attendance via the DB function.
  static Future<Map<String, dynamic>> validateAndMarkAttendance({
    required String? sessionId,
    required String token,
    required String studentId,
    required String studentName,
    required String method,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final res = await _client.rpc('validate_and_mark_attendance', params: {
      'p_session_id': sessionId,
      'p_token': token.toUpperCase(),
      'p_student_id': studentId,
      'p_student_name': studentName,
      'p_method': method,
      'p_user_id': userId,
    });

    // Handle case where PostgREST wraps JSONB result in an array
    if (res is List && res.isNotEmpty) {
      final first = res[0];
      if (first is Map<String, dynamic>) return first;
    }

    if (res is Map<String, dynamic>) return res;
    // If the result is a string (shouldn't happen), parse it
    return {'success': false, 'error': 'Unexpected response format'};
  }

  // ─── Reports ───────────────────────────────────────────────────────────────

  /// Fetch attendance records joined with session data for the admin report.
  static Future<List<Map<String, dynamic>>> getAttendanceReport({
    int? semester,
    String? subject,
    DateTime? dateFrom,
    DateTime? dateTo,
    TimeOfDay? timeFrom,
    TimeOfDay? timeTo,
  }) async {
    // Build a query that joins records with session info
    var query = _client.from('attendance_records').select('''
      id, student_id, student_name, method, marked_at,
      attendance_sessions!inner(
        id, department, subject, semester, teacher_id, created_at
      )
    ''');

    if (semester != null) {
      query = query.eq('attendance_sessions.semester', semester);
    }
    if (subject != null && subject.isNotEmpty) {
      query = query.eq('attendance_sessions.subject', subject);
    }

    // Date/time filtering on marked_at
    if (dateFrom != null || dateTo != null || timeFrom != null || timeTo != null) {
      // Convert to UTC ISO strings for Supabase query
      final localNow = DateTime.now();

      String? startFilter;
      String? endFilter;

      if (dateFrom != null && timeFrom != null) {
        // Specific date + time
        startFilter = DateTime(
          dateFrom.year, dateFrom.month, dateFrom.day,
          timeFrom.hour, timeFrom.minute,
        ).toUtc().toIso8601String();
      } else if (dateFrom != null) {
        // Date only — start of day in local time, converted to UTC
        startFilter = DateTime(
          dateFrom.year, dateFrom.month, dateFrom.day,
        ).toUtc().toIso8601String();
      } else if (timeFrom != null) {
        // Time only — apply to current date
        startFilter = DateTime(
          localNow.year, localNow.month, localNow.day,
          timeFrom.hour, timeFrom.minute,
        ).toUtc().toIso8601String();
      }

      if (dateTo != null && timeTo != null) {
        endFilter = DateTime(
          dateTo.year, dateTo.month, dateTo.day,
          timeTo.hour, timeTo.minute, 59,
        ).toUtc().toIso8601String();
      } else if (dateTo != null) {
        endFilter = DateTime(
          dateTo.year, dateTo.month, dateTo.day, 23, 59, 59,
        ).toUtc().toIso8601String();
      } else if (timeTo != null) {
        endFilter = DateTime(
          localNow.year, localNow.month, localNow.day,
          timeTo.hour, timeTo.minute, 59,
        ).toUtc().toIso8601String();
      }

      if (startFilter != null) {
        query = query.gte('marked_at', startFilter);
      }
      if (endFilter != null) {
        query = query.lte('marked_at', endFilter);
      }
    }

    final res = await query.order('marked_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ─── Student History ──────────────────────────────────────────────────────

  /// Fetch a student's own attendance records and per-subject stats.
  /// Calls the SECURITY DEFINER RPC to bypass RLS on attendance_sessions.
  static Future<Map<String, dynamic>> getStudentAttendance(String studentId) async {
    final res = await _client.rpc('get_student_attendance', params: {
      'p_student_id': studentId,
    });
    if (res is Map<String, dynamic>) return res;
    return {'records': [], 'stats': []};
  }

  /// Fetch all sessions (for admin filtering).
  static Future<List<Map<String, dynamic>>> getAllSessions({
    int? semester,
    String? subject,
  }) async {
    var query = _client.from('attendance_sessions').select();
    if (semester != null) query = query.eq('semester', semester);
    if (subject != null && subject.isNotEmpty) {
      query = query.eq('subject', subject);
    }
    final res = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ─── Delete Own Record ──────────────────────────────────────────────────

  /// Delete a student's own attendance record (must be marked by them).
  /// Relies on the RLS policy `attendance_records_delete_own` which allows
  /// deletion when `marked_by = auth.uid()`.
  static Future<void> deleteAttendanceRecord(String recordId) async {
    await _client.from('attendance_records').delete().eq('id', recordId);
  }

  /// Get aggregated attendance stats per student per subject.
  /// Returns: [{student_id, student_name, subject, semester, total_sessions, attended, percentage}]
  static Future<List<Map<String, dynamic>>> getAttendanceStats({
    int? semester,
    String? subject,
    DateTime? dateFrom,
    DateTime? dateTo,
    TimeOfDay? timeFrom,
    TimeOfDay? timeTo,
  }) async {
    // Fetch all sessions matching filters
    var sessionQuery = _client.from('attendance_sessions').select('id, subject, semester');
    if (semester != null) sessionQuery = sessionQuery.eq('semester', semester);
    if (subject != null && subject.isNotEmpty) {
      sessionQuery = sessionQuery.eq('subject', subject);
    }
    final sessions = await sessionQuery;
    if (sessions.isEmpty) return [];

    final sessionIds = sessions.map((s) => s['id'] as String).toList();

    // Build records query with optional date/time filtering
    var recordsQuery = _client
        .from('attendance_records')
        .select('student_id, student_name, session_id, marked_at')
        .inFilter('session_id', sessionIds);

    // Apply date/time filter on marked_at
    if (dateFrom != null || dateTo != null || timeFrom != null || timeTo != null) {
      final localNow = DateTime.now();

      String? startFilter;
      String? endFilter;

      if (dateFrom != null && timeFrom != null) {
        startFilter = DateTime(
          dateFrom.year, dateFrom.month, dateFrom.day,
          timeFrom.hour, timeFrom.minute,
        ).toUtc().toIso8601String();
      } else if (dateFrom != null) {
        startFilter = DateTime(
          dateFrom.year, dateFrom.month, dateFrom.day,
        ).toUtc().toIso8601String();
      } else if (timeFrom != null) {
        startFilter = DateTime(
          localNow.year, localNow.month, localNow.day,
          timeFrom.hour, timeFrom.minute,
        ).toUtc().toIso8601String();
      }

      if (dateTo != null && timeTo != null) {
        endFilter = DateTime(
          dateTo.year, dateTo.month, dateTo.day,
          timeTo.hour, timeTo.minute, 59,
        ).toUtc().toIso8601String();
      } else if (dateTo != null) {
        endFilter = DateTime(
          dateTo.year, dateTo.month, dateTo.day, 23, 59, 59,
        ).toUtc().toIso8601String();
      } else if (timeTo != null) {
        endFilter = DateTime(
          localNow.year, localNow.month, localNow.day,
          timeTo.hour, timeTo.minute, 59,
        ).toUtc().toIso8601String();
      }

      if (startFilter != null) recordsQuery = recordsQuery.gte('marked_at', startFilter);
      if (endFilter != null) recordsQuery = recordsQuery.lte('marked_at', endFilter);
    }

    final records = await recordsQuery;

    // Build session lookup
    final sessionMap = <String, Map<String, dynamic>>{};
    for (final s in sessions) {
      sessionMap[s['id'] as String] = s;
    }

    // Aggregate: group by student_id + subject
    final statsMap = <String, Map<String, dynamic>>{};
    for (final r in records) {
      final sid = r['session_id'] as String;
      final studentId = r['student_id'] as String;
      final studentName = r['student_name'] as String;
      final session = sessionMap[sid];
      if (session == null) continue;

      final subj = session['subject'] as String;
      final sem = session['semester'] as int;
      final key = '$studentId|$subj|$sem';

      statsMap.putIfAbsent(key, () => {
        'student_id': studentId,
        'student_name': studentName,
        'subject': subj,
        'semester': sem,
        'attended': 0,
      });
      statsMap[key]!['attended'] = (statsMap[key]!['attended'] as int) + 1;
    }

    // Count total sessions per subject+semester
    final sessionCountMap = <String, int>{};
    for (final s in sessions) {
      final subj = s['subject'] as String;
      final sem = s['semester'] as int;
      final key = '$subj|$sem';
      sessionCountMap[key] = (sessionCountMap[key] ?? 0) + 1;
    }

    // Calculate percentages
    final result = <Map<String, dynamic>>[];
    for (final entry in statsMap.entries) {
      final stat = entry.value;
      final subj = stat['subject'] as String;
      final sem = stat['semester'] as int;
      final total = sessionCountMap['$subj|$sem'] ?? 1;
      final attended = stat['attended'] as int;
      final pct = (attended / total * 100).round();

      result.add({
        ...stat,
        'total_sessions': total,
        'percentage': pct,
      });
    }

    // Sort by student_id
    result.sort((a, b) => (a['student_id'] as String).compareTo(b['student_id'] as String));
    return result;
  }
}
