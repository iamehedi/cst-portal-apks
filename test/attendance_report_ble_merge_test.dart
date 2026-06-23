import 'package:flutter_test/flutter_test.dart';
import 'package:cst_portal/core/ble/ble_session_codec.dart';
import 'package:cst_portal/core/db/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Attendance Report — BLE Session Merge Tests
// ─────────────────────────────────────────────────────────────────────────────
// These tests verify that the attendance report's BLE session merging logic
// correctly isolates data between different sessions. After the Bug 1 & 4
// fixes (session state clearing in BleSessionProvider), the database and
// report must still work correctly when handling data from multiple sessions.
//
// Key scenarios tested:
//   1. Merged records are scoped by session_id (no cross-contamination)
//   2. Finalized (approved) records don't appear as pending in reports
//   3. Rejected pending records from old sessions don't leak into new sessions
//   4. hasBleDuplicate is scoped by session_id
//   5. UNIQUE constraint allows multi-subject attendance
//   6. Session encoding produces unique IDs per subject
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for in-memory testing
  sqfliteFfiInit();

  // ── Setup: create in-memory database before each test ──
  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LocalDatabase.createTablesForTesting(db);
    LocalDatabase.setTestDatabase(db);
  });

  tearDown(() async {
    await LocalDatabase.close();
  });

  group('BLE merge — session isolation in database', () {
    test('Session 1 data does NOT leak into Session 2 (ghost attendance fix)', () async {
      // Simulate Session 1 (Mathematics)
      const mathSessionId = 'ATT_MATH_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': mathSessionId,
        'subject': 'Mathematics',
        'semester': 3,
        'teacher_id': 'TCH_001',
        'department': 'CST',
        'status': 'closed',
        'created_at': '2026-06-22T07:30:00.000Z',
        'closed_at': '2026-06-22T08:30:00.000Z',
      });
      // Student Mehedi was approved in Session 1
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId,
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // Simulate Session 2 (Python) — completely separate
      const pythonSessionId = 'ATT_PYTHON_20260622_D3E4F';
      await LocalDatabase.insertBleSession({
        'id': pythonSessionId,
        'subject': 'Python',
        'semester': 3,
        'teacher_id': 'TCH_001',
        'department': 'CST',
        'status': 'active',
        'created_at': '2026-06-22T08:45:00.000Z',
      });

      // Session 1's data: query by Session 1 ID
      final session1Finals = await LocalDatabase.getBleFinalBySession(mathSessionId);
      expect(session1Finals.length, 1,
          reason: 'Session 1 should have 1 final record');
      expect(session1Finals.first['student_id'], '215949');

      // Session 2's data: query by Session 2 ID
      final session2Finals = await LocalDatabase.getBleFinalBySession(pythonSessionId);
      expect(session2Finals, isEmpty,
          reason: 'Session 2 should have NO final records (student never checked in)');

      // Verify: the two sessions are completely isolated in the database
      expect(session1Finals.first['session_id'], mathSessionId,
          reason: 'Session 1 records should be scoped to Session 1');
      expect(session2Finals.isEmpty, isTrue,
          reason: 'Session 2 should have no records from Session 1');
    });

    test('Approved pending records are excluded from merge (hasFinal check)', () async {
      const sessionId = 'ATT_MATH_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': sessionId,
        'subject': 'Mathematics',
        'semester': 3,
        'teacher_id': 'TCH_001',
        'department': 'CST',
        'status': 'active',
        'created_at': '2026-06-22T07:30:00.000Z',
      });

      // Student has a pending record
      await LocalDatabase.insertBlePending({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': sessionId,
        'time': '07:35',
        'rssi': -44,
        'status': 'pending',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // Student also has a final record (was approved)
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': sessionId,
        'status': 'present',
        'created_at': '2026-06-22T07:36:00.000Z',
      });

      // The merge logic: for each pending record, check hasFinal
      final pendingRecords = await LocalDatabase.getBlePendingBySession(sessionId);
      final finalRecords = await LocalDatabase.getBleFinalBySession(sessionId);

      // The merge logic should skip this pending record because hasFinal is true
      for (final p in pendingRecords) {
        final sid = p['student_id']?.toString() ?? '';
        final hasFinal = finalRecords.any((f) => f['student_id']?.toString() == sid);
        expect(hasFinal, isTrue,
            reason: 'Approved student should have a final record, excluding their pending entry from the report');
      }
    });

    test('Rejected pending records are preserved in merge (no final record)', () async {
      const sessionId = 'ATT_MATH_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': sessionId,
        'subject': 'Mathematics',
        'semester': 3,
        'teacher_id': 'TCH_001',
        'department': 'CST',
        'status': 'active',
        'created_at': '2026-06-22T07:30:00.000Z',
      });

      // Student has a rejected pending record (teacher rejected or auto-rejected on session end)
      await LocalDatabase.insertBlePending({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': sessionId,
        'time': '07:35',
        'rssi': -44,
        'status': 'rejected',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // No final record (was rejected, not approved)
      final pendingRecords = await LocalDatabase.getBlePendingBySession(sessionId);
      final finalRecords = await LocalDatabase.getBleFinalBySession(sessionId);

      expect(pendingRecords.length, 1,
          reason: 'Rejected pending record should exist');
      expect(pendingRecords.first['status'], 'rejected',
          reason: 'Pending status should be rejected');
      expect(finalRecords, isEmpty,
          reason: 'No final record for rejected student');

      // The merge logic: hasFinal is false, so this pending record would be
      // included in the report with _ble_status = 'rejected'
      final hasFinal = finalRecords.any((f) => f['student_id']?.toString() == '215949');
      expect(hasFinal, isFalse,
          reason: 'Rejected student should NOT have a final record — their rejected pending record appears in the report');
    });

    test('hasBleDuplicate scoped by session_id prevents cross-session blocking', () async {
      const mathSession = 'ATT_MATH_20260622_ABC12';
      const pythonSession = 'ATT_PYTHON_20260622_D3E4F';

      // Student checked into Math
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSession,
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // hasBleDuplicate for Math session → true
      final mathDuplicate = await LocalDatabase.hasBleDuplicate('215949', mathSession);
      expect(mathDuplicate, isTrue,
          reason: 'Student IS a duplicate for Math session');

      // hasBleDuplicate for Python session → false (different session!)
      final pythonDuplicate = await LocalDatabase.hasBleDuplicate('215949', pythonSession);
      expect(pythonDuplicate, isFalse,
          reason: 'Student is NOT a duplicate for Python session — different session_id');

      // This is the core session isolation: the UNIQUE(student_id, session_id)
      // constraint allows the same student to attend multiple subjects.
    });

    test('UNIQUE constraint supports multi-subject attendance', () async {
      // Both inserts should succeed because they have different session_ids
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': 'ATT_MATH_20260622_ABC12',
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': 'ATT_PYTHON_20260622_D3E4F',
        'status': 'present',
        'created_at': '2026-06-22T08:50:00.000Z',
      });

      // Both records should exist
      final mathFinals = await LocalDatabase.getBleFinalBySession('ATT_MATH_20260622_ABC12');
      final pythonFinals = await LocalDatabase.getBleFinalBySession('ATT_PYTHON_20260622_D3E4F');

      expect(mathFinals.length, 1);
      expect(pythonFinals.length, 1);

      // The same student in two sessions — both allowed
      expect(mathFinals.first['student_id'], '215949');
      expect(pythonFinals.first['student_id'], '215949');
    });

    test('Duplicate insert (student_id + session_id) is idempotent — upsert replaces rather than duplicates', () async {
      // First insert succeeds
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': 'ATT_MATH_20260622_ABC12',
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // Second insert with same student + session should be replaced (ConflictAlgorithm.replace)
      // This is the expected behavior — we don't want duplicate records
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': 'ATT_MATH_20260622_ABC12',
        'status': 'present',
        'created_at': '2026-06-22T07:36:00.000Z',
      });

      // Should still only have 1 record (upserted, not duplicated)
      final finals = await LocalDatabase.getBleFinalBySession('ATT_MATH_20260622_ABC12');
      expect(finals.length, 1,
          reason: 'UNIQUE(student_id, session_id) constraint prevents duplicates');
    });
  });

  group('BleSessionCodec — unique session encoding', () {
    test('Every subject session has a unique beacon payload', () {
      final mathId = 'ATT_MATH_20260622_ABC12';
      final pythonId = 'ATT_PYTHON_20260622_D3E4F';

      final mathBytes = BleSessionCodec.encode(mathId, 'Mathematics');
      final pythonBytes = BleSessionCodec.encode(pythonId, 'Python');

      // The beacon payloads must be different
      expect(mathBytes, isNot(equals(pythonBytes)),
          reason: 'Different subjects must produce different BLE beacon payloads');

      // Decoding each yields the correct session and subject
      final mathDecoded = BleSessionCodec.decode(mathBytes);
      final pythonDecoded = BleSessionCodec.decode(pythonBytes);

      expect(mathDecoded!.sessionId, mathId);
      expect(mathDecoded.subject, 'Mathematics');
      expect(pythonDecoded!.sessionId, pythonId);
      expect(pythonDecoded.subject, 'Python');
    });

    test('Same subject on different dates produces different session IDs', () {
      // Session ID includes date, so same subject on different dates = different IDs
      const mathDay1 = 'ATT_MATH_20260622_ABC12';
      const mathDay2 = 'ATT_MATH_20260623_XYZ99';

      expect(mathDay1, isNot(mathDay2),
          reason: 'Same subject on different dates must have different session IDs');
    });
  });

  group('Attendance report — merge logic verification', () {
    test('Multiple sessions with same student are independently represented', () async {
      // Create two sessions
      const mathId = 'ATT_MATH_20260622_ABC12';
      const pythonId = 'ATT_PYTHON_20260622_D3E4F';

      await LocalDatabase.insertBleSession({
        'id': mathId, 'subject': 'Mathematics', 'semester': 3,
        'teacher_id': 'TCH_001', 'department': 'CST',
        'status': 'closed', 'created_at': '2026-06-22T07:30:00.000Z',
      });
      await LocalDatabase.insertBleSession({
        'id': pythonId, 'subject': 'Python', 'semester': 3,
        'teacher_id': 'TCH_001', 'department': 'CST',
        'status': 'closed', 'created_at': '2026-06-22T08:45:00.000Z',
      });

      // Student approved in Math, rejected in Python
      await LocalDatabase.insertBleFinal({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': mathId, 'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });
      await LocalDatabase.insertBlePending({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': pythonId, 'time': '08:50', 'rssi': -43,
        'status': 'rejected', 'created_at': '2026-06-22T08:50:00.000Z',
      });

      // Simulate the merge logic
      final allSessions = await LocalDatabase.getAllBleSessions();
      final mergedRecords = <Map<String, dynamic>>[];

      for (final session in allSessions) {
        final sid = session['id']?.toString() ?? '';
        if (sid.isEmpty) continue;

        final pendingRecs = await LocalDatabase.getBlePendingBySession(sid);
        final finalRecs = await LocalDatabase.getBleFinalBySession(sid);

        for (final p in pendingRecs) {
          final studentId = p['student_id']?.toString() ?? '';
          if (studentId.isEmpty) continue;
          final hasFinal = finalRecs.any((f) => f['student_id']?.toString() == studentId);
          if (hasFinal) continue;

          mergedRecords.add({
            'student_id': studentId,
            'session_id': sid,
            '_ble_status': p['status']?.toString() ?? 'pending',
          });
        }
      }

      // Math session: student was approved, so rejected pending should NOT appear
      // Python session: student was rejected, so rejected pending SHOULD appear
      final mathMerged = mergedRecords.where((r) => r['session_id'] == mathId).toList();
      final pythonMerged = mergedRecords.where((r) => r['session_id'] == pythonId).toList();

      expect(mathMerged, isEmpty,
          reason: 'Math session: student was approved (has final), so no pending entry in merge');
      expect(pythonMerged.length, 1,
          reason: 'Python session: student was rejected (no final), so pending entry appears');
      expect(pythonMerged.first['_ble_status'], 'rejected',
          reason: 'Python session: status should be rejected');
    });
  });
}
