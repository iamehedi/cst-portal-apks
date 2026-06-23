import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/db/local_database.dart';
import '../core/sync/sync_manager.dart';
import '../services/connectivity_service.dart';
import 'supabase_service.dart';

class AttendanceService {
  static SupabaseClient get _client => SupabaseService.client;
  static const _uuid = Uuid();

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
        id, department, subject, semester, teacher_id, created_at, class_date, class_time
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

  // ─── Offline-First Session Creation ─────────────────────────

  /// Build the session map used when creating a session offline.
  /// Exposed for unit testing — mirrors the map built inside
  /// [createSessionOfflineFirst] for the offline fallback path.
  @visibleForTesting
  static Map<String, dynamic> buildOfflineSessionMap({
    required String id,
    required String teacherId,
    required String department,
    required String subject,
    required int semester,
    String? classDate,
    String? classTime,
    required String createdAt,
  }) {
    return {
      'id': id,
      'teacher_id': teacherId,
      'department': department,
      'subject': subject,
      'semester': semester,
      'is_active': true,
      'class_date': classDate,
      'class_time': classTime,
      'created_at': createdAt,
      'sync_status': 'pending',
      'offline': true,
    };
  }

  /// Create a session with offline-first approach:
  /// - If online: creates via Supabase
  /// - If offline: generates a local UUID and saves to SQLite
  /// The session will sync to Supabase when connectivity is restored.
  static Future<Map<String, dynamic>> createSessionOfflineFirst({
    required String department,
    required String subject,
    required int semester,
    String? classDate,
    String? classTime,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final now = DateTime.now().toUtc().toIso8601String();

    if (ConnectivityService().isOnline.value) {
      try {
        return await createSession(
          department: department,
          subject: subject,
          semester: semester,
          classDate: classDate,
          classTime: classTime,
        );
      } catch (_) {
        // Fall through to local save
      }
    }

    // Offline or server error: create locally
    final localSession = {
      'id': _uuid.v4(),
      'department': department,
      'subject': subject,
      'semester': semester,
      'teacher_id': userId,
      'class_date': classDate,
      'class_time': classTime,
      'is_active': true,
      'created_at': now,
      'sync_status': 'pending',
    };

    await LocalDatabase.insertQrSession(localSession);
    final attendanceCount = await LocalDatabase.getPendingCount();
    final qrCount = await LocalDatabase.getQrPendingCount();
    SyncManager().pendingCount.value = attendanceCount + qrCount;
    SyncManager().sessionPendingCount.value = qrCount;

    return buildOfflineSessionMap(
      id: localSession['id'] as String,
      teacherId: userId,
      department: department,
      subject: subject,
      semester: semester,
      classDate: classDate,
      classTime: classTime,
      createdAt: now,
    );
  }

  /// Sync a locally-created QR session to Supabase.
  /// Creates the session record + pushes all pending attendance records for it.
  static Future<void> syncQrSession(Map<String, dynamic> session) async {
    final sessionId = session['id']?.toString() ?? '';
    if (sessionId.isEmpty) return;

    try {
      // Create the Supabase session record
      final created = await createSession(
        department: session['department']?.toString() ?? '',
        subject: session['subject']?.toString() ?? '',
        semester: session['semester'] is int
            ? session['semester'] as int
            : int.tryParse(session['semester']?.toString() ?? '0') ?? 0,
        classDate: session['class_date']?.toString(),
        classTime: session['class_time']?.toString(),
      );
      final serverId = created['id']?.toString();

      // If session was closed offline, end it on server too
      if (serverId != null && (session['is_active'] == 0 || session['is_active'] == false)) {
        await endSession(serverId);
      }

      // Push any local attendance records for this session
      final localRecords = await LocalDatabase.getAllLocalAttendance();
      for (final record in localRecords) {
        if (record['session_id']?.toString() == sessionId) {
          record['session_id'] = serverId ?? sessionId;
          try {
            await _client.from('attendance_records').upsert({
              'session_id': serverId ?? sessionId,
              'student_id': record['student_id']?.toString() ?? '',
              'student_name': record['student_name']?.toString() ?? '',
              'method': record['method']?.toString() ?? 'manual',
              'marked_by': record['device_id']?.toString() ?? session['teacher_id'],
              'marked_at': record['scanned_at']?.toString() ?? record['created_at']?.toString(),
            }, onConflict: 'session_id,student_id');
          } catch (_) {}
        }
      }

      await LocalDatabase.markQrSessionSynced(sessionId);
      if (serverId != null) {
        // Update local attendance records with the real server session ID
        await LocalDatabase.markQrAttendancePending(sessionId);
      }
    } catch (e) {
      debugPrint('[AttendanceService] syncQrSession error: $e');
    }
  }

  /// Sync all unsynced QR sessions.
  static Future<int> syncAllQrSessions() async {
    int count = 0;
    try {
      final sessions = await LocalDatabase.getUnsyncedQrSessions();
      for (final session in sessions) {
        await syncQrSession(session);
        count++;
      }
    } catch (_) {}
    return count;
  }

  // ─── Offline-First Attendance ──────────────────────────────

  /// Mark attendance with offline-first approach:
  /// - If online: calls server-side validation immediately
  /// - If offline: saves locally with pending sync status
  /// Returns a map with 'success' bool and optional 'offline' flag.
  static Future<Map<String, dynamic>> markAttendanceOfflineFirst({
    required String? sessionId,
    required String token,
    required String studentId,
    required String studentName,
    required String method,
  }) async {
    if (ConnectivityService().isOnline.value) {
      try {
        return await validateAndMarkAttendance(
          sessionId: sessionId,
          token: token,
          studentId: studentId,
          studentName: studentName,
          method: method,
        );
      } catch (e) {
        // Fall through to offline save on any network error
      }
    }

    // Offline or server error: save locally
    final now = DateTime.now().toUtc().toIso8601String();
    final record = {
      'id': _uuid.v4(),
      'student_id': studentId,
      'student_name': studentName,
      'class': '',
      'subject': '',
      'session_id': sessionId ?? '',
      'status': 'present',
      'scanned_at': now,
      'sync_status': 'pending',
      'retry_count': 0,
      'token': token.toUpperCase(),
      'method': method,
      'device_id': SupabaseService.currentUser?.id ?? '',
      'created_at': now,
    };

    try {
      await LocalDatabase.insertAttendanceLocal(record);
      final attCount = await LocalDatabase.getPendingCount();
      final sesCount = await LocalDatabase.getQrPendingCount();
      SyncManager().pendingCount.value = attCount + sesCount;
      SyncManager().sessionPendingCount.value = sesCount;
      return {'success': true, 'offline': true, 'message': 'Attendance saved offline. Will sync when online.'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to save attendance locally: $e'};
    }
  }

  /// Check for duplicate offline scan.
  static Future<bool> isDuplicateOffline(String studentId, String subject, String scannedAt) async {
    return LocalDatabase.isDuplicateScan(studentId, subject, scannedAt);
  }

  /// Get pending sync count.
  static Future<int> getPendingCount() => LocalDatabase.getPendingCount();

  /// Get all local attendance records.
  static Future<List<Map<String, dynamic>>> getLocalRecords() => LocalDatabase.getAllLocalAttendance();

  /// Trigger manual sync.
  static Future<int> manualSync() => SyncManager().manualSync();

  // ─── Delete Own Record ──────────────────────────────────────────────────

  /// Delete a student's own attendance record (must be marked by them).
  /// Relies on the RLS policy `attendance_records_delete_own` which allows
  /// deletion when `marked_by = auth.uid()`.
  static Future<void> deleteAttendanceRecord(String recordId) async {
    await _client.from('attendance_records').delete().eq('id', recordId);
  }

  // ─── Unified BLE Attendance (ble_sessions + attendance_sessions/attendance_records) ──

  /// Create (or return existing) unified [attendance_sessions] record for a BLE session.
  /// Stores the UUID back into [ble_sessions.unified_session_id].
  static Future<String?> ensureUnifiedBleSession(Map<String, dynamic> bleSession) async {
    final existingUuid = bleSession['unified_session_id']?.toString();
    if (existingUuid != null && existingUuid.isNotEmpty) return existingUuid;

    try {
      final created = await createSession(
        department: bleSession['department']?.toString() ?? '',
        subject: bleSession['subject']?.toString() ?? '',
        semester: bleSession['semester'] is int
            ? bleSession['semester'] as int
            : int.tryParse(bleSession['semester']?.toString() ?? '0') ?? 0,
      );
      final uuid = created['id']?.toString();
      if (uuid != null) {
        // Persist the UUID back locally so we don't re-create
        final sid = bleSession['id']?.toString() ?? '';
        if (sid.isNotEmpty) {
          final db = await LocalDatabase.database;
          await db.update(
            LocalDatabase.tableBleSessions,
            {'unified_session_id': uuid},
            where: 'id = ?',
            whereArgs: [sid],
          );
        }
        // Also upsert into ble_sessions supabase table with the uuid
        try {
          await _client.from('ble_sessions').upsert({
            'id': bleSession['id'],
            'subject': bleSession['subject'],
            'semester': bleSession['semester'],
            'teacher_id': bleSession['teacher_id'],
            'department': bleSession['department'],
            'status': bleSession['status'] ?? 'active',
            'created_at': bleSession['created_at'],
            if (bleSession['closed_at'] != null) 'closed_at': bleSession['closed_at'],
            'unified_session_id': uuid,
          });
        } catch (_) {}
        return uuid;
      }
    } catch (_) {}
    return null;
  }

  /// Insert a BLE final attendance record into [attendance_records] (unified table).
  /// Requires [unifiedSessionId] (UUID of the corresponding attendance_sessions row).
  static Future<void> insertBleAttendanceRecord({
    required String unifiedSessionId,
    required String studentId,
    required String studentName,
    required String status,
    required String markedAt,
  }) async {
    try {
      await _client.from('attendance_records').insert({
        'session_id': unifiedSessionId,
        'student_id': studentId,
        'student_name': studentName,
        'method': 'ble',
        'marked_by': SupabaseService.currentUser?.id,
        'marked_at': markedAt,
      });
    } catch (_) {}
  }

  /// Sync a BLE final record to both the legacy [ble_final_attendance] table
  /// AND the unified [attendance_records] table.
  static Future<void> syncBleFinal(Map<String, dynamic> record) async {
    try {
      await _client.from('ble_final_attendance').upsert({
        'student_id': record['student_id'],
        'session_id': record['session_id'],
        'status': record['status'] ?? 'present',
        'created_at': record['created_at'],
      });
    } catch (_) {}

    // Unified: also write to attendance_records (teacher-side only;
    // student-side will be reconciled via syncBleSessionFull)
    final bleSessionId = record['session_id']?.toString() ?? '';
    if (bleSessionId.isNotEmpty) {
      final sessions = await LocalDatabase.getAllBleSessions();
      final session = sessions.where((s) => s['id'] == bleSessionId).firstOrNull;
      if (session != null) {
        String? uuid = session['unified_session_id']?.toString();
        if (uuid == null || uuid.isEmpty) {
          uuid = await ensureUnifiedBleSession(session);
        }
        if (uuid != null) {
          final studentId = record['student_id']?.toString() ?? '';
          final studentName = record['student_name']?.toString() ?? studentId;
          final createdAt = record['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
          try {
            await _client.from('attendance_records').upsert({
              'session_id': uuid,
              'student_id': studentId,
              'student_name': studentName,
              'method': 'ble',
              'marked_by': SupabaseService.currentUser?.id,
              'marked_at': createdAt,
            }, onConflict: 'session_id,student_id');
          } catch (_) {}
        }
      }
    }
  }

  /// Sync a BLE pending record to Supabase (legacy table only; no unified equivalent).
  static Future<void> syncBlePending(Map<String, dynamic> record) async {
    try {
      await _client.from('ble_pending_attendance').upsert({
        'id': record['id'],
        'session_id': record['session_id'],
        'student_id': record['student_id'],
        'student_name': record['student_name'],
        'time': record['time'],
        'rssi': record['rssi'] ?? 0,
        'status': record['status'] ?? 'pending',
        'created_at': record['created_at'],
      });
    } catch (_) {}
  }

  /// Ensure unified [attendance_sessions] + [attendance_records] exist for a BLE session.
  static Future<void> syncBleSessionFull(String bleSessionId) async {
    try {
      final sessions = await LocalDatabase.getAllBleSessions();
      final session = sessions.where((s) => s['id'] == bleSessionId).firstOrNull;
      if (session == null) return;

      // Ensure unified session exists
      final uuid = await ensureUnifiedBleSession(session);
      if (uuid == null) return;

      // Sync BLE session to legacy table
      try {
        await _client.from('ble_sessions').upsert({
          'id': session['id'],
          'subject': session['subject'],
          'semester': session['semester'],
          'teacher_id': session['teacher_id'],
          'department': session['department'],
          'status': session['status'] ?? 'active',
          'created_at': session['created_at'],
          if (session['closed_at'] != null) 'closed_at': session['closed_at'],
        });
      } catch (_) {}

      // Sync final records → attendance_records (no duplicates due to unique index)
      final finals = await LocalDatabase.getBleFinalBySession(bleSessionId);
      for (final fr in finals) {
        final studentId = fr['student_id']?.toString() ?? '';
        if (studentId.isEmpty) continue;
        final studentName = fr['student_name']?.toString() ?? studentId;
        final createdAt = fr['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
        try {
          await _client.from('attendance_records').upsert({
            'session_id': uuid,
            'student_id': studentId,
            'student_name': studentName,
            'method': 'ble',
            'marked_by': session['teacher_id'],
            'marked_at': createdAt,
          }, onConflict: 'session_id,student_id');
        } catch (_) {}
        // Also sync to legacy ble_final_attendance
        try {
          await _client.from('ble_final_attendance').upsert({
            'student_id': studentId,
            'session_id': bleSessionId,
            'status': fr['status'] ?? 'present',
            'created_at': createdAt,
          });
        } catch (_) {}
      }

      // Sync pending records
      final pendings = await LocalDatabase.getBlePendingBySession(bleSessionId);
      for (final r in pendings) {
        await syncBlePending(r);
      }
    } catch (_) {}
  }

  /// Sync ALL local BLE sessions + records to both legacy and unified tables.
  static Future<int> syncAllBleRecords() async {
    int count = 0;
    try {
      final sessions = await LocalDatabase.getAllBleSessions();
      for (final session in sessions) {
        final sid = session['id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        await syncBleSessionFull(sid);
        count++;
      }
    } catch (_) {}
    return count;
  }

  /// Delete from unified [attendance_records] (BLE records only).
  static Future<void> _deleteUnifiedRecord(String sessionId, String studentId) async {
    try {
      await _client.from('attendance_records').delete()
          .eq('session_id', sessionId)
          .eq('student_id', studentId)
          .eq('method', 'ble');
    } catch (_) {}
  }

  /// Delete a BLE attendance record from all tables (local + legacy + unified).
  /// [recordId] format: 'ble_<localId>' or 'ble_pending_<localId>'.
  static Future<void> deleteBleRecord(String recordId) async {
    if (recordId.startsWith('ble_pending_')) {
      final idStr = recordId.substring('ble_pending_'.length);
      final localId = int.tryParse(idStr);
      if (localId == null) return;
      await LocalDatabase.deleteBlePendingById(localId);
      try {
        await _client.from('ble_pending_attendance').delete().eq('id', localId);
      } catch (_) {}
      return;
    }

    // For final records, find via the record's context passed from UI
    // or fallback to scanning local DB
    if (recordId.startsWith('ble_')) {
      final idStr = recordId.substring('ble_'.length);
      final localId = int.tryParse(idStr);
      if (localId == null) return;

      final sessions = await LocalDatabase.getAllBleSessions();
      for (final session in sessions) {
        final sid = session['id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final finals = await LocalDatabase.getBleFinalBySession(sid);
        for (final fr in finals) {
          if (fr['id'] == localId) {
            final studentId = fr['student_id']?.toString() ?? '';
            // Delete from local
            await LocalDatabase.deleteBleFinal(sid, studentId);
            // Delete from legacy ble_final_attendance
            try {
              await _client.from('ble_final_attendance').delete()
                  .eq('session_id', sid)
                  .eq('student_id', studentId);
            } catch (_) {}
            // Delete from unified attendance_records
            final uuid = session['unified_session_id']?.toString();
            if (uuid != null && uuid.isNotEmpty) {
              await _deleteUnifiedRecord(uuid, studentId);
            }
            return;
          }
        }
      }
    }
  }

  /// Delete a BLE session from all tables.
  static Future<void> deleteBleSession(String bleSessionId) async {
    final sessions = await LocalDatabase.getAllBleSessions();
    final session = sessions.where((s) => s['id'] == bleSessionId).firstOrNull;
    final uuid = session?['unified_session_id']?.toString();

    await LocalDatabase.deleteBleSession(bleSessionId);
    try {
      await _client.from('ble_pending_attendance').delete().eq('session_id', bleSessionId);
      await _client.from('ble_final_attendance').delete().eq('session_id', bleSessionId);
      await _client.from('ble_sessions').delete().eq('id', bleSessionId);
    } catch (_) {}

    if (uuid != null && uuid.isNotEmpty) {
      try {
        await _client.from('attendance_records').delete().eq('session_id', uuid);
        await _client.from('attendance_sessions').delete().eq('id', uuid);
      } catch (_) {}
    }
  }

  /// Delete a single BLE final record (local + legacy + unified).
  static Future<void> deleteBleFinalBySessionAndStudent(String bleSessionId, String studentId) async {
    await LocalDatabase.deleteBleFinal(bleSessionId, studentId);
    try {
      await _client.from('ble_final_attendance').delete()
          .eq('session_id', bleSessionId)
          .eq('student_id', studentId);
    } catch (_) {}

    // Also delete from unified
    final sessions = await LocalDatabase.getAllBleSessions();
    final session = sessions.where((s) => s['id'] == bleSessionId).firstOrNull;
    final uuid = session?['unified_session_id']?.toString();
    if (uuid != null && uuid.isNotEmpty) {
      await _deleteUnifiedRecord(uuid, studentId);
    }
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
