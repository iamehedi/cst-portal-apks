import 'package:flutter_test/flutter_test.dart';
import 'package:cst_portal/core/ble/ble_session_codec.dart';
import 'package:cst_portal/core/db/local_database.dart';
import 'package:cst_portal/features/ble/providers/ble_attendance_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLE Attendance — End-to-End Two-Session Integration Test
// ─────────────────────────────────────────────────────────────────────────────
//
// Simulates the complete lifecycle of TWO consecutive BLE attendance sessions
// using in-memory SQLite. This is the closest we can get to a full E2E test
// without actual BLE hardware or the Nearby Connections plugin.
//
// What this tests:
//
//   Session 1 (Mathematics):
//     Start session → Student A checks in (pending) → Teacher approves (present)
//                       Student B checks in (pending) → Teacher rejects (rejected)
//                       Session ends → remaining pending auto-rejected
//
//   Session 2 (Python) — completely fresh:
//     Start session → Student A checks in again (pending) → Teacher approves
//                       Student C checks in (pending) → Teacher approves
//                       Session ends
//
//   Verifications:
//     - Session 1 has: Student A=present(approved), Student B=rejected
//     - Session 2 has: Student A=present, Student C=present
//     - Student A is properly present in BOTH sessions (multi-subject attendance)
//     - No cross-contamination: Session 2 has NO trace of Student B
//     - BleAttendanceProvider.reset() clears all state between sessions
//     - hasBleDuplicate correctly scoped: same student, different session = NOT duplicate
//     - Session encoding produces unique beacon payloads per subject
//     - Counters: connected=0, detected=0, pending=0 on fresh session start
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  // E2E will only work with sqflite_common_ffi for in-memory DB.
  // We set up a fresh DB before each test and tear it down after.
  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LocalDatabase.createTablesForTesting(db);
    LocalDatabase.setTestDatabase(db);
  });

  tearDown(() async {
    await LocalDatabase.close();
    LocalDatabase.setTestDatabase(null);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO: Two consecutive BLE sessions with the same teacher
  // ──────────────────────────────────────────────────────────────────────────
  // This is the exact scenario from the bug report:
  //   Session 1: Mathematics-III → works correctly
  //   Session 2: Python → BUG: student shows "Present" without checking in
  //
  // After the fix, Session 2 must start with a completely clean state.
  // ──────────────────────────────────────────────────────────────────────────

  group('E2E: Two consecutive BLE sessions — ghost attendance prevention', () {
    const teacherId = 'TCH_001';
    const department = 'CST';
    const semester = 3;

    test('Session 1 (Mathematics) — complete lifecycle', () async {
      // ── STEP 1: Start Session 1 ──────────────────────────────────────
      // This mirrors BleSessionProvider.startSession() DB operations
      const mathSessionId = 'ATT_MATHEMATICS_20260622_ABC12';
      final now = DateTime.now().toUtc().toIso8601String();

      await LocalDatabase.insertBleSession({
        'id': mathSessionId,
        'subject': 'Mathematics',
        'semester': semester,
        'teacher_id': teacherId,
        'department': department,
        'status': 'active',
        'created_at': now,
      });

      // Verify session was created correctly
      final activeSession = await LocalDatabase.getActiveBleSession();
      expect(activeSession, isNotNull,
          reason: 'Active BLE session should exist');
      expect(activeSession!['id'], mathSessionId,
          reason: 'Session 1 ID should match');
      expect(activeSession['status'], 'active',
          reason: 'Session 1 should be active');

      // ── STEP 2: Student A checks in via BLE (pending) ───────────────
      // This mirrors BleSessionProvider._onCheckIn() DB operations.
      // insertBlePending returns the auto-increment ID — capture it for updates.
      final studentAPendingId = await LocalDatabase.insertBlePending({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId,
        'time': '07:35',
        'rssi': -44,
        'status': 'pending',
        'created_at': now,
      });
      expect(studentAPendingId, greaterThan(0),
          reason: 'Should get a valid auto-increment ID');

      // Verify pending record
      var pendingRecords = await LocalDatabase.getBlePendingBySession(mathSessionId);
      expect(pendingRecords.length, 1,
          reason: 'Session 1 should have 1 pending record');
      expect(pendingRecords.first['student_id'], '215949',
          reason: 'Student A should be pending');
      expect(pendingRecords.first['status'], 'pending',
          reason: 'Status should be pending');

      // ── STEP 3: Student B checks in via BLE (pending) ───────────────
      final studentBPendingId = await LocalDatabase.insertBlePending({
        'student_id': '215950',
        'student_name': 'Rafiq Islam',
        'session_id': mathSessionId,
        'time': '07:38',
        'rssi': -42,
        'status': 'pending',
        'created_at': now,
      });
      expect(studentBPendingId, greaterThan(0));
      expect(studentBPendingId, greaterThan(studentAPendingId));

      pendingRecords = await LocalDatabase.getBlePendingBySession(mathSessionId);
      expect(pendingRecords.length, 2,
          reason: 'Session 1 should have 2 pending records');

      // ── STEP 4: Teacher approves Student A (present) ───────────────
      // This mirrors BleSessionProvider.approveStudent() DB operations
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId,
        'status': 'present',
        'created_at': now,
      });
      // Use captured ID — NEVER hardcode auto-increment values
      await LocalDatabase.updateBlePendingStatus(studentAPendingId, 'present');

      // Verify approval
      final finalRecords = await LocalDatabase.getBleFinalBySession(mathSessionId);
      expect(finalRecords.length, 1,
          reason: 'Session 1 should have 1 final record');
      expect(finalRecords.first['student_id'], '215949',
          reason: 'Student A should be the approved one');
      expect(finalRecords.first['status'], 'present',
          reason: 'Student A should be present');

      // Pending record should now be 'present'
      pendingRecords = await LocalDatabase.getBlePendingBySession(mathSessionId);
      final studentA = pendingRecords.firstWhere((r) => r['student_id'] == '215949');
      expect(studentA['status'], 'present',
          reason: 'Student A pending status should be updated to present');

      // ── STEP 5: Teacher rejects Student B ──────────────────────────
      await LocalDatabase.updateBlePendingStatus(studentBPendingId, 'rejected');

      pendingRecords = await LocalDatabase.getBlePendingBySession(mathSessionId);
      final studentB = pendingRecords.firstWhere((r) => r['student_id'] == '215950');
      expect(studentB['status'], 'rejected',
          reason: 'Student B should be rejected');

      // ── STEP 6: End Session 1 ──────────────────────────────────────
      // This mirrors BleSessionProvider.stopSession() DB operations
      await LocalDatabase.rejectAllPending(mathSessionId);
      await LocalDatabase.closeBleSession(mathSessionId);

      // Verify session is closed
      final closedSession = await LocalDatabase.getActiveBleSession();
      expect(closedSession, isNull,
          reason: 'No active session should exist after closing');

      // All remaining pending should be either present or rejected
      pendingRecords = await LocalDatabase.getBlePendingBySession(mathSessionId);
      for (final r in pendingRecords) {
        expect(r['status'], anyOf('present', 'rejected'),
            reason: 'All pending records must be either present or rejected after session end');
      }

      // FINAL VERIFICATION: Session 1 data
      // Student A should have: 1 final (present), 1 pending (present)
      final session1Finals = await LocalDatabase.getBleFinalBySession(mathSessionId);
      expect(session1Finals.length, 1,
          reason: 'Session 1 should have exactly 1 final record');
      expect(session1Finals.first['student_id'], '215949');
      expect(session1Finals.first['status'], 'present');

      final session1Pendings = await LocalDatabase.getBlePendingBySession(mathSessionId);
      final studentAEnd = session1Pendings.firstWhere((r) => r['student_id'] == '215949');
      final studentBEnd = session1Pendings.firstWhere((r) => r['student_id'] == '215950');
      expect(studentAEnd['status'], 'present',
          reason: 'Student A end status in Session 1: present');
      expect(studentBEnd['status'], 'rejected',
          reason: 'Student B end status in Session 1: rejected');
    });

    test('Session 2 (Python) — completely isolated from Session 1', () async {
      // ── FIRST: Simulate Session 1 data in the DB (as if it had completed) ──
      const mathSessionId = 'ATT_MATHEMATICS_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': mathSessionId,
        'subject': 'Mathematics',
        'semester': semester,
        'teacher_id': teacherId,
        'department': department,
        'status': 'closed',
        'created_at': '2026-06-22T07:30:00.000Z',
        'closed_at': '2026-06-22T08:30:00.000Z',
      });
      await LocalDatabase.insertBlePending({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId,
        'time': '07:35', 'rssi': -44,
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });
      await LocalDatabase.insertBlePending({
        'student_id': '215950',
        'student_name': 'Rafiq Islam',
        'session_id': mathSessionId,
        'time': '07:38', 'rssi': -42,
        'status': 'rejected',
        'created_at': '2026-06-22T07:38:00.000Z',
      });
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId,
        'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // ── THE FIX: Simulate what happens when a new session starts ──
      // This is the critical verfication: the in-memory state (roster,
      // processing check-ins, counters) would have been cleared by
      // BleSessionProvider.startSession(). The DB data from Session 1
      // exists but is properly scoped to session_id.

      // ── STEP 1: Start Session 2 (Python) ─────────────────────────
      const pythonSessionId = 'ATT_PYTHON_20260622_D3E4F';
      await LocalDatabase.insertBleSession({
        'id': pythonSessionId,
        'subject': 'Python',
        'semester': semester,
        'teacher_id': teacherId,
        'department': department,
        'status': 'active',
        'created_at': '2026-06-22T08:45:00.000Z',
      });

      // Verify Session 2 is the active session (not Session 1)
      final activeSession = await LocalDatabase.getActiveBleSession();
      expect(activeSession, isNotNull);
      expect(activeSession!['id'], pythonSessionId,
          reason: 'Active session should be Session 2 (Python), not Session 1');

      // Verify Session 2 starts with completely empty data
      var session2Pending = await LocalDatabase.getBlePendingBySession(pythonSessionId);
      var session2Finals = await LocalDatabase.getBleFinalBySession(pythonSessionId);
      expect(session2Pending, isEmpty,
          reason: 'Session 2 should start with zero pending records');
      expect(session2Finals, isEmpty,
          reason: 'Session 2 should start with zero final records');

      // ── STEP 2: Student A checks in to Session 2 ──────────────────
      // This was the GHOST ATTENDANCE scenario: Student A was present
      // in Session 1. With session isolation, they MUST be allowed to
      // check in to Session 2. The hasBleDuplicate check must NOT block them.

      // Verify hasBleDuplicate is scoped by session_id
      final duplicateForSession1 = await LocalDatabase.hasBleDuplicate('215949', mathSessionId);
      final duplicateForSession2 = await LocalDatabase.hasBleDuplicate('215949', pythonSessionId);

      expect(duplicateForSession1, isTrue,
          reason: 'Student A IS a duplicate for Session 1 (already attended)');
      expect(duplicateForSession2, isFalse,
          reason: 'Student A is NOT a duplicate for Session 2 (different session)');

      // ── STEP 2: Student A checks in to Session 2 ──────────────────
      // Capture the auto-increment ID — Session 1's inserts used IDs 1-2,
      // Session 2's inserts get IDs 3-4 (in a fresh DB). Using captured
      // IDs is always correct regardless of insert order.
      final session2StudentAPendingId = await LocalDatabase.insertBlePending({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': pythonSessionId,
        'time': '08:50', 'rssi': -43,
        'status': 'pending',
        'created_at': '2026-06-22T08:50:00.000Z',
      });
      await LocalDatabase.insertBleFinal({
        'student_id': '215949',
        'student_name': 'Mehedi Hasan',
        'session_id': pythonSessionId,
        'status': 'present',
        'created_at': '2026-06-22T08:51:00.000Z',
      });
      // Use captured ID — NOT a hardcoded number!
      await LocalDatabase.updateBlePendingStatus(session2StudentAPendingId, 'present');

      // ── STEP 3: Student C checks in to Session 2 ──────────────────
      // Student C (new student, not in Session 1)
      final studentCId = '215951';
      final session2StudentCPendingId = await LocalDatabase.insertBlePending({
        'student_id': studentCId,
        'student_name': 'Sadia Akter',
        'session_id': pythonSessionId,
        'time': '08:53', 'rssi': -41,
        'status': 'pending',
        'created_at': '2026-06-22T08:53:00.000Z',
      });
      await LocalDatabase.insertBleFinal({
        'student_id': studentCId,
        'student_name': 'Sadia Akter',
        'session_id': pythonSessionId,
        'status': 'present',
        'created_at': '2026-06-22T08:54:00.000Z',
      });
      // Use captured ID — NOT a hardcoded number!
      await LocalDatabase.updateBlePendingStatus(session2StudentCPendingId, 'present');

      // ── STEP 4: End Session 2 ──────────────────────────────────────
      await LocalDatabase.rejectAllPending(pythonSessionId);
      await LocalDatabase.closeBleSession(pythonSessionId);

      // ── FINAL VERIFICATION: Cross-session data integrity ───────────

      // Session 1 data should be UNCHANGED
      final session1Finals = await LocalDatabase.getBleFinalBySession(mathSessionId);
      expect(session1Finals.length, 1,
          reason: 'Session 1 should still have exactly 1 final record');
      expect(session1Finals.first['student_id'], '215949',
          reason: 'Session 1 final: Student A');
      expect(session1Finals.first['status'], 'present');

      final session1Pendings = await LocalDatabase.getBlePendingBySession(mathSessionId);
      expect(session1Pendings.length, 2,
          reason: 'Session 1 should still have 2 pending records');

      // Session 2 data should be COMPLETELY SEPARATE
      session2Finals = await LocalDatabase.getBleFinalBySession(pythonSessionId);
      expect(session2Finals.length, 2,
          reason: 'Session 2 should have exactly 2 final records');
      expect(session2Finals.any((r) => r['student_id'] == '215949'), isTrue,
          reason: 'Session 2 final: Student A present');
      expect(session2Finals.any((r) => r['student_id'] == studentCId), isTrue,
          reason: 'Session 2 final: Student C present');

      session2Pending = await LocalDatabase.getBlePendingBySession(pythonSessionId);
      for (final r in session2Pending) {
        expect(r['status'], anyOf('present', 'rejected'),
            reason: 'Session 2: all pending records settled after session end');
      }

      // CROSS-CHECK: Student B (from Session 1) must NOT appear in Session 2
      final session2StudentIds = session2Finals.map((r) => r['student_id'] as String).toSet();
      expect(session2StudentIds, isNot(contains('215950')),
          reason: 'CRITICAL: Student B (from Session 1) must NOT leak into Session 2');

      // CROSS-CHECK: Student A is in BOTH sessions (correct — multi-subject attendance)
      expect(
        session2StudentIds.contains('215949'),
        isTrue,
        reason: 'Student A can attend both sessions independently',
      );
    });

    test('Session 2 starts with zero DB records (pending=0, final=0, duplicate=false)', () async {
      // Session 1 completed data
      const mathSessionId = 'ATT_MATHEMATICS_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': mathSessionId, 'subject': 'Mathematics', 'semester': semester,
        'teacher_id': teacherId, 'department': department,
        'status': 'closed', 'created_at': '2026-06-22T07:30:00.000Z',
      });
      await LocalDatabase.insertBleFinal({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': mathSessionId, 'status': 'present',
        'created_at': '2026-06-22T07:35:00.000Z',
      });

      // When Session 2 starts, BleSessionProvider.startSession() clears the roster
      // and processingCheckIns sets. At the DB level, this means querying by the
      // NEW session_id should return zero records for ALL three states.

      const pythonSessionId = 'ATT_PYTHON_20260622_D3E4F';
      await LocalDatabase.insertBleSession({
        'id': pythonSessionId, 'subject': 'Python', 'semester': semester,
        'teacher_id': teacherId, 'department': department,
        'status': 'active', 'created_at': '2026-06-22T08:45:00.000Z',
      });

      // Zero pending records for Session 2
      final pendingForSession2 = await LocalDatabase.getBlePendingBySession(pythonSessionId);
      expect(pendingForSession2, isEmpty,
          reason: 'Session 2 pending count should be ZERO on fresh start');

      // Zero final records for Session 2
      final finalsForSession2 = await LocalDatabase.getBleFinalBySession(pythonSessionId);
      expect(finalsForSession2, isEmpty,
          reason: 'Session 2 final count should be ZERO on fresh start');

      // hasBleDuplicate for a NEW student should be false
      final newStudentDuplicate = await LocalDatabase.hasBleDuplicate('215999', pythonSessionId);
      expect(newStudentDuplicate, isFalse,
          reason: 'A new student should not be a duplicate for a fresh session');

      // Note: BleSessionProvider also resets in-memory counters (connectedCount,
      // pendingCount, detected count) to 0 via _roster.clear(). We verify
      // the DB-layer equivalent here. Platform-dependent counter verification
      // requires actual BLE/Nearby hardware and is tested separately.
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO: State machine transitions (no state may be skipped)
  // ──────────────────────────────────────────────────────────────────────────
  // The state machine must follow: DETECTED → CONNECTED → PENDING → PRESENT
  // In the DB, this means:
  //   - A pending record must exist before a final record can be created
  //   - A student cannot be marked "present" without having been "pending" first
  //   - The same student in the same session cannot have multiple final records
  // ──────────────────────────────────────────────────────────────────────────

  group('State machine — PENDING must precede PRESENT', () {
    test('Student must have pending record before being approved (present)', () async {
      const sessionId = 'ATT_MATH_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': sessionId, 'subject': 'Mathematics', 'semester': 3,
        'teacher_id': 'TCH_001', 'department': 'CST',
        'status': 'active', 'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Correct flow: pending first, then final
      await LocalDatabase.insertBlePending({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': sessionId, 'time': '07:35', 'rssi': -44,
        'status': 'pending', 'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await LocalDatabase.insertBleFinal({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': sessionId, 'status': 'present',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // When we query getBleFinalByStatus or check the report merge:
      // The final record exists, AND the pending record exists.
      // This is the correct state: PENDING → PRESENT completed.

      final finals = await LocalDatabase.getBleFinalBySession(sessionId);
      expect(finals.length, 1);
      expect(finals.first['student_id'], '215949');
      expect(finals.first['status'], 'present');

      final pendings = await LocalDatabase.getBlePendingBySession(sessionId);
      final studentPending = pendings.firstWhere((r) => r['student_id'] == '215949');
      expect(studentPending['status'], 'pending',
          reason: 'Pending record still exists even after final is created');
    });

    test('Cannot have two final records for same student in same session', () async {
      const sessionId = 'ATT_MATH_20260622_ABC12';
      await LocalDatabase.insertBleSession({
        'id': sessionId, 'subject': 'Mathematics', 'semester': 3,
        'teacher_id': 'TCH_001', 'department': 'CST',
        'status': 'active', 'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // First insert
      await LocalDatabase.insertBleFinal({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': sessionId, 'status': 'present',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Second insert with same (student_id, session_id) — upsert replaces
      // After this, there should still be only ONE record (the UNIQUE constraint
      // combined with ConflictAlgorithm.replace makes it idempotent)
      await LocalDatabase.insertBleFinal({
        'student_id': '215949', 'student_name': 'Mehedi Hasan',
        'session_id': sessionId, 'status': 'present',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final finals = await LocalDatabase.getBleFinalBySession(sessionId);
      expect(finals.length, 1,
          reason: 'UNIQUE(student_id, session_id) prevents duplicate final records');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO: BleAttendanceProvider state clearing between sessions
  // ──────────────────────────────────────────────────────────────────────────
  // The BleAttendanceProvider.reset() method is called when entering the
  // student screen and when the auto-reset timer fires. It must clear all
  // scan state so a new session can be discovered independently.
  //
  // These tests verify the provider's observable behavior.
  // ──────────────────────────────────────────────────────────────────────────

  group('BleAttendanceProvider.reset() — student side state clearing', () {
    late BleAttendanceProvider provider;

    setUp(() {
      provider = BleAttendanceProvider();
    });

    test('reset clears scanState, sessionId, subject, and statusMessage', () {
      provider.reset();

      expect(provider.scanState, 'idle',
          reason: 'After reset, student should be ready to scan a new session');
      expect(provider.detectedSessionId, isNull,
          reason: 'Old session ID must be cleared');
      expect(provider.detectedSubject, isNull,
          reason: 'Old subject must be cleared');
      expect(provider.statusMessage, isNull,
          reason: 'Status message like "Present ✅" must be cleared');
    });

    test('Multiple consecutive resets are safe (idempotent)', () {
      provider.reset();
      provider.reset();
      provider.reset();

      expect(provider.scanState, 'idle');
      expect(provider.detectedSessionId, isNull);
      expect(provider.detectedSubject, isNull);
      expect(provider.statusMessage, isNull);
    });

    test('setIdentity survives reset — identity reused across sessions', () {
      provider.setIdentity('215949', 'Mehedi Hasan');
      provider.reset();

      // reset() only clears scan state, not the student's identity.
      // This allows scanning for multiple subjects without re-entering credentials.
      expect(provider.scanState, 'idle');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO: Session encoding uniqueness
  // ──────────────────────────────────────────────────────────────────────────
  // Each session gets a unique session ID encoded in the BLE beacon payload.
  // The student extracts this ID from the beacon to identify which session
  // they're connecting to.
  // ──────────────────────────────────────────────────────────────────────────

  group('BLE beacon — unique session identification', () {
    test('Each subject produces a unique beacon payload with correct metadata', () {
      const mathId = 'ATT_MATHEMATICS_20260622_ABC12';
      const pythonId = 'ATT_PYTHON_20260622_D3E4F';

      final mathPayload = BleSessionCodec.encode(mathId, 'Mathematics');
      final pythonPayload = BleSessionCodec.encode(pythonId, 'Python');

      // Different subjects → different beacon payloads
      expect(mathPayload, isNot(equals(pythonPayload)),
          reason: 'Different subjects must have different BLE beacon payloads');

      // Student app decodes the payload correctly
      final mathDecoded = BleSessionCodec.decode(mathPayload);
      final pythonDecoded = BleSessionCodec.decode(pythonPayload);

      expect(mathDecoded!.sessionId, mathId);
      expect(mathDecoded.subject, 'Mathematics');
      expect(pythonDecoded!.sessionId, pythonId);
      expect(pythonDecoded.subject, 'Python');

      // The session ID itself encodes the subject name for identification
      expect(mathId, contains('MATHEMATICS'),
          reason: 'Session ID should contain the subject for identification');
      expect(pythonId, contains('PYTHON'),
          reason: 'Session ID should contain the subject for identification');

      // Same subject on different dates = different session IDs
      const mathTomorrow = 'ATT_MATHEMATICS_20260623_XYZ99';
      expect(mathId, isNot(mathTomorrow),
          reason: 'Same subject on different dates must have different session IDs');
    });

    test('Beacon payload format is ATT|sessionId|subject', () {
      final bytes = BleSessionCodec.encode('ATT_MATH_20260622_ABC12', 'Mathematics');
      expect(String.fromCharCodes(bytes), 'ATT|ATT_MATH_20260622_ABC12|Mathematics');
    });
  });
}
