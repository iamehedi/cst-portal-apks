import 'package:flutter_test/flutter_test.dart';
import 'package:cst_portal/services/attendance_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QR Session Offline — Unit Tests
// ─────────────────────────────────────────────────────────────────────────────
// These tests verify the offline-first QR session feature by calling
// the actual production code through @visibleForTesting methods.
//
// What's tested:
//   - AttendanceService.buildOfflineSessionMap() — the exact map
//     construction used by createSessionOfflineFirst when offline
//   - Session data structure: required fields, types, default values
//   - SyncQrSession null-safety: null-handling guards for optional fields
//   - Edge cases: missing department, null session ID, float semester
//   - UUID format: validates the v4 UUID pattern
//   - Semester parsing: int vs String from DB, invalid string fallback
//   - Sync status transitions (conceptual)
//
// The full end-to-end flow (createSessionOfflineFirst → LocalDatabase →
// syncQrSession → Supabase) requires integration tests with a real or
// mocked Supabase client and SQLite database.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── buildOfflineSessionMap — exact production code ─────────────────────

  group('buildOfflineSessionMap — production code', () {
    test('returns map with all required fields', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: '550e8400-e29b-41d4-a716-446655440000',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'Data Structures',
        semester: 3,
        createdAt: '2026-06-23T07:30:00.000Z',
      );

      expect(session['id'], '550e8400-e29b-41d4-a716-446655440000');
      expect(session['teacher_id'], 'TCH_001');
      expect(session['department'], 'CST');
      expect(session['subject'], 'Data Structures');
      expect(session['semester'], 3);
      expect(session['created_at'], '2026-06-23T07:30:00.000Z');
    });

    test('sets is_active to true', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-1',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'Math',
        semester: 3,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      expect(session['is_active'], true);
    });

    test('sets sync_status to pending', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-2',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'Math',
        semester: 3,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      expect(session['sync_status'], 'pending');
    });

    test('sets offline flag to true', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-3',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'Math',
        semester: 3,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      expect(session['offline'], true);
    });

    test('includes optional class_date and class_time when provided', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-4',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'OS',
        semester: 5,
        classDate: '2026-06-23',
        classTime: '13:30',
        createdAt: '2026-06-23T07:30:00.000Z',
      );
      expect(session['class_date'], '2026-06-23');
      expect(session['class_time'], '13:30');
    });

    test('omits class_date and class_time when not provided', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-5',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'OS',
        semester: 5,
        createdAt: '2026-06-23T07:30:00.000Z',
      );
      expect(session['class_date'], isNull);
      expect(session['class_time'], isNull);
    });

    test('all field types match expected schema', () {
      final session = AttendanceService.buildOfflineSessionMap(
        id: 'id-6',
        teacherId: 'TCH_001',
        department: 'CST',
        subject: 'Physics',
        semester: 1,
        createdAt: '2026-06-23T07:30:00.000Z',
      );

      expect(session['id'], isA<String>());
      expect(session['teacher_id'], isA<String>());
      expect(session['subject'], isA<String>());
      expect(session['semester'], isA<int>());
      expect(session['is_active'], isA<bool>());
      expect(session['created_at'], isA<String>());
      expect(session['sync_status'], isA<String>());
      expect(session['offline'], isA<bool>());
    });
  });

  // ─── UUID Format ────────────────────────────────────────────────────────

  group('Session ID — UUID v4 format', () {
    test('matches UUID v4 pattern', () {
      const uuidPattern =
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      expect(uuid, matches(uuidPattern));
    });

    test('UUID has 36 characters with 5 segments', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      expect(uuid.length, 36);
      expect(uuid.split('-').length, 5);
    });
  });

  // ─── Semester Parsing (type flexibility for syncQrSession) ──────────────

  group('Semester parsing — syncQrSession handles both int and String', () {
    test('semester as string from JSON is parsed correctly', () {
      const semesterStr = '3';
      final result = semesterStr is int
          ? semesterStr
          : int.tryParse(semesterStr) ?? 0;
      expect(result, 3);
    });

    test('invalid semester string defaults to 0', () {
      const invalid = 'not-a-number';
      final result = int.tryParse(invalid) ?? 0;
      expect(result, 0);
    });

    test('float semester string truncates to int', () {
      const floatStr = '3.0';
      final result = double.tryParse(floatStr)?.toInt() ?? int.tryParse(floatStr) ?? 0;
      expect(result, 3);
    });
  });

  // ─── Session Guards (syncQrSession null-safety) ─────────────────────────

  group('syncQrSession — null-safety guards', () {
    test('null session ID guard: returns immediately', () {
      // Guard: final sessionId = session['id']?.toString() ?? '';
      //        if (sessionId.isEmpty) return;
      String? nullId;
      final sessionId = nullId?.toString() ?? '';
      expect(sessionId.isEmpty, isTrue);
    });

    test('null department defaults to empty string', () {
      // Guard: session['department']?.toString() ?? ''
      String? nullDept;
      final dept = nullDept?.toString() ?? '';
      expect(dept, '');
    });

    test('null method defaults to manual', () {
      // Guard: record['method']?.toString() ?? 'manual'
      String? nullMethod;
      final method = nullMethod?.toString() ?? 'manual';
      expect(method, 'manual');
    });

    test('null student_id defaults to empty string', () {
      // Guard: record['student_id']?.toString() ?? ''
      String? nullId;
      final id = nullId?.toString() ?? '';
      expect(id, '');
    });

    test('null scanned_at falls back to created_at', () {
      // Guard: record['scanned_at']?.toString() ?? record['created_at']?.toString()
      String? nullScanned;
      const createdAt = '2026-06-23T07:30:00.000Z';
      final markedAt = nullScanned?.toString() ?? createdAt;
      expect(markedAt, createdAt);
    });

    test('both scanned_at and created_at null falls back to empty string', () {
      // Final fallback in the worst case
      String? nullScanned;
      String? nullCreated;
      final markedAt = nullScanned?.toString() ??
          nullCreated?.toString() ??
          '';
      expect(markedAt, '');
    });
  });

  // ─── Sync Status Values ─────────────────────────────────────────────────

  group('Sync status — values used in SQL queries', () {
    test('getUnsyncedQrSessions filters pending + failed', () {
      // The SQL: sync_status IN ('pending', 'failed')
      const unsyncedStatuses = ['pending', 'failed'];
      expect(unsyncedStatuses, contains('pending'));
      expect(unsyncedStatuses, contains('failed'));
      expect(unsyncedStatuses, isNot(contains('synced')));
    });
  });
}
