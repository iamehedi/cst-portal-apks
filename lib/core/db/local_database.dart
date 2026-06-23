import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart' as p;

class LocalDatabase {
  static Database? _db;
  static const String _dbName = 'cst_portal_offline.db';
  static const int _dbVersion = 4;

  /// Initialize database factory for the current platform.
  /// On web, FFI-backed SQLite (WebAssembly) is required.
  static void initFactory() {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
  }

  static const String tableAttendanceLocal = 'attendance_local';
  static const String tableStudentsCache = 'students_cache';

  // Smart attendance tables
  static const String tableBleSessions = 'ble_sessions';
  static const String tableBlePending = 'ble_pending_attendance';
  static const String tableBleFinal = 'ble_final_attendance';

  // QR session table (offline-first)
  static const String tableQrSessions = 'qr_sessions';

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  /// Replace the internal DB instance with a custom one (for testing).
  /// Pass `null` to reset so the next `database` getter re-creates it.
  @visibleForTesting
  static void setTestDatabase(Database? db) {
    _db = db;
  }

  /// Database version used for test database creation.
  @visibleForTesting
  static int get dbVersionForTesting => _dbVersion;

  /// Run table creation logic (mirrors [_onCreate]).
  @visibleForTesting
  static Future<void> createTablesForTesting(Database db) => _onCreate(db, _dbVersion);

  static Future<Database> _initDatabase() async {
    initFactory();
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableStudentsCache (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        roll_no TEXT,
        class TEXT,
        section TEXT,
        photo_url TEXT,
        last_synced_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableAttendanceLocal (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        student_name TEXT,
        class TEXT,
        subject TEXT,
        session_id TEXT,
        status TEXT NOT NULL DEFAULT 'present',
        scanned_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        token TEXT,
        method TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_attendance_sync_status 
      ON $tableAttendanceLocal (sync_status)
    ''');

    await db.execute('''
      CREATE INDEX idx_attendance_student 
      ON $tableAttendanceLocal (student_id, subject, class)
    ''');

    await db.execute('''
      CREATE INDEX idx_students_cache_name
      ON $tableStudentsCache (name)
    ''');

    // ── BLE tables (v2) ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableBleSessions (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        semester INTEGER NOT NULL,
        teacher_id TEXT NOT NULL,
        department TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        closed_at TEXT,
        unified_session_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableBlePending (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL,
        student_name TEXT NOT NULL,
        session_id TEXT NOT NULL,
        time TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableBleFinal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL,
        student_name TEXT NOT NULL DEFAULT '',
        session_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'present',
        created_at TEXT NOT NULL,
        UNIQUE(student_id, session_id)
      )
    ''');

    // ── QR Sessions (v4) ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableQrSessions (
        id TEXT PRIMARY KEY,
        department TEXT,
        subject TEXT NOT NULL,
        semester INTEGER NOT NULL,
        teacher_id TEXT NOT NULL,
        class_date TEXT,
        class_time TEXT,
        current_token TEXT,
        token_created_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        closed_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableBleSessions (
          id TEXT PRIMARY KEY,
          subject TEXT NOT NULL,
          semester INTEGER NOT NULL,
          teacher_id TEXT NOT NULL,
          department TEXT,
          status TEXT NOT NULL DEFAULT 'active',
          created_at TEXT NOT NULL,
          closed_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableBlePending (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id TEXT NOT NULL,
          student_name TEXT NOT NULL,
          session_id TEXT NOT NULL,
          time TEXT NOT NULL,
          rssi INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableBleFinal (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id TEXT NOT NULL,
          student_name TEXT NOT NULL,
          session_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'present',
          created_at TEXT NOT NULL,
          UNIQUE(student_id, session_id)
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE $tableBleSessions ADD COLUMN unified_session_id TEXT
      ''');

      // Fix: add missing student_name column for v2 fresh install users.
      // SQLite will throw if column already exists (v1→v2 upgrade already has it).
      try {
        await db.execute('''
          ALTER TABLE $tableBleFinal ADD COLUMN student_name TEXT NOT NULL DEFAULT ''
        ''');
      } catch (_) {
        // Column already exists — safe to ignore
      }
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableQrSessions (
          id TEXT PRIMARY KEY,
          department TEXT,
          subject TEXT NOT NULL,
          semester INTEGER NOT NULL,
          teacher_id TEXT NOT NULL,
          class_date TEXT,
          class_time TEXT,
          current_token TEXT,
          token_created_at TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          closed_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'pending'
        )
      ''');
    }
  }

  static Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
      _db = null;
    }
  }

  // ─── Students Cache ────────────────────────────────────────────

  static Future<void> cacheStudents(List<Map<String, dynamic>> students) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();

    for (final s in students) {
      batch.insert(
        tableStudentsCache,
        {
          'id': s['id']?.toString() ?? '',
          'name': s['name']?.toString() ?? '',
          'roll_no': s['roll']?.toString() ?? s['roll_no']?.toString(),
          'class': s['class']?.toString(),
          'section': s['section']?.toString(),
          'photo_url': s['photo_url']?.toString(),
          'last_synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedStudents() async {
    final db = await database;
    return db.query(tableStudentsCache, orderBy: 'name ASC');
  }

  static Future<Map<String, dynamic>?> getCachedStudent(String id) async {
    final db = await database;
    final rows = await db.query(
      tableStudentsCache,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<Map<String, dynamic>?> findCachedStudentByQuery(String query) async {
    final db = await database;
    final q = '%$query%';
    final rows = await db.query(
      tableStudentsCache,
      where: 'name LIKE ? OR roll_no LIKE ? OR id LIKE ?',
      whereArgs: [q, q, q],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<void> clearStudentsCache() async {
    final db = await database;
    await db.delete(tableStudentsCache);
  }

  // ─── Attendance Local ──────────────────────────────────────────

  static Future<void> insertAttendanceLocal(Map<String, dynamic> record) async {
    final db = await database;
    await db.insert(
      tableAttendanceLocal,
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingRecords() async {
    final db = await database;
    return db.query(
      tableAttendanceLocal,
      where: 'sync_status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getSyncedRecords() async {
    final db = await database;
    return db.query(
      tableAttendanceLocal,
      where: 'sync_status = ?',
      whereArgs: ['synced'],
      orderBy: 'created_at DESC',
      limit: 100,
    );
  }

  static Future<List<Map<String, dynamic>>> getAllLocalAttendance() async {
    final db = await database;
    return db.query(
      tableAttendanceLocal,
      orderBy: 'created_at DESC',
      limit: 200,
    );
  }

  static Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $tableAttendanceLocal WHERE sync_status IN ('pending', 'failed')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> markRecordSynced(String id) async {
    final db = await database;
    await db.update(
      tableAttendanceLocal,
      {'sync_status': 'synced', 'retry_count': 0, 'last_attempt_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markRecordFailed(String id, {int maxRetries = 5}) async {
    final db = await database;
    final record = await db.query(tableAttendanceLocal, where: 'id = ?', whereArgs: [id], limit: 1);
    if (record.isEmpty) return;
    final currentRetries = (record.first['retry_count'] as int?) ?? 0;
    await db.update(
      tableAttendanceLocal,
      {
        'sync_status': currentRetries >= maxRetries ? 'failed' : 'failed',
        'retry_count': currentRetries + 1,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<bool> isDuplicateScan(String studentId, String subject, String scannedAt) async {
    final db = await database;
    final dateStr = scannedAt.substring(0, 10);
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $tableAttendanceLocal WHERE student_id = ? AND subject = ? AND substr(scanned_at, 1, 10) = ?",
      [studentId, subject, dateStr],
    );
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  static Future<void> deleteOldSyncedRecords({int daysOld = 90}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: daysOld)).toUtc().toIso8601String();
    await db.delete(
      tableAttendanceLocal,
      where: "sync_status = 'synced' AND created_at < ?",
      whereArgs: [cutoff],
    );
  }

  // ─── BLE Sessions ─────────────────────────────────────────────

  static Future<void> insertBleSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert(tableBleSessions, session, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getActiveBleSession() async {
    final db = await database;
    final rows = await db.query(
      tableBleSessions,
      where: 'status = ?',
      whereArgs: ['active'],
      limit: 1,
      orderBy: 'created_at DESC',
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<void> closeBleSession(String sessionId) async {
    final db = await database;
    await db.update(
      tableBleSessions,
      {'status': 'closed', 'closed_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  static Future<List<Map<String, dynamic>>> getAllBleSessions() async {
    final db = await database;
    return db.query(tableBleSessions, orderBy: 'created_at DESC');
  }

  // ─── BLE Pending Attendance ───────────────────────────────────

  static Future<int> insertBlePending(Map<String, dynamic> record) async {
    final db = await database;
    return db.insert(tableBlePending, record);
  }

  static Future<List<Map<String, dynamic>>> getBlePendingBySession(String sessionId) async {
    final db = await database;
    return db.query(
      tableBlePending,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> updateBlePendingStatus(int id, String status) async {
    final db = await database;
    await db.update(
      tableBlePending,
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getBlePendingByStudent(String studentId) async {
    final db = await database;
    return db.query(
      tableBlePending,
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'created_at DESC',
    );
  }

  static Future<bool> hasBleDuplicate(String studentId, String sessionId) async {
    final db = await database;
    final pendingResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $tableBlePending WHERE student_id = ? AND session_id = ?",
      [studentId, sessionId],
    );
    if ((Sqflite.firstIntValue(pendingResult) ?? 0) > 0) return true;
    final finalResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $tableBleFinal WHERE student_id = ? AND session_id = ?",
      [studentId, sessionId],
    );
    return (Sqflite.firstIntValue(finalResult) ?? 0) > 0;
  }

  // ─── BLE Final Attendance ─────────────────────────────────────

  static Future<void> insertBleFinal(Map<String, dynamic> record) async {
    final db = await database;
    await db.insert(tableBleFinal, record, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getBleFinalBySession(String sessionId) async {
    final db = await database;
    return db.query(
      tableBleFinal,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  static Future<String?> getBleFinalStatus(String studentId, String sessionId) async {
    final db = await database;
    final rows = await db.query(
      tableBleFinal,
      where: 'student_id = ? AND session_id = ?',
      whereArgs: [studentId, sessionId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first['status'] as String? : null;
  }

  static Future<void> rejectAllPending(String sessionId) async {
    final db = await database;
    await db.update(
      tableBlePending,
      {'status': 'rejected'},
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'pending'],
    );
  }

  // ─── BLE Delete Methods ──────────────────────────────────────

  /// Delete an entire BLE session and all its pending + final records.
  static Future<void> deleteBleSession(String sessionId) async {
    final db = await database;
    final batch = db.batch();
    batch.delete(
      tableBleFinal,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    batch.delete(
      tableBlePending,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    batch.delete(
      tableBleSessions,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await batch.commit(noResult: true);
  }

  /// Delete a single BLE final attendance record by session + student.
  static Future<void> deleteBleFinal(String sessionId, String studentId) async {
    final db = await database;
    await db.delete(
      tableBleFinal,
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
    );
  }

  /// Delete a BLE pending record by its local id.
  static Future<void> deleteBlePendingById(int id) async {
    final db = await database;
    await db.delete(
      tableBlePending,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all pending records for a session.
  static Future<void> deleteBlePendingBySession(String sessionId) async {
    final db = await database;
    await db.delete(
      tableBlePending,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ─── QR Sessions (offline-first) ───────────────────────────────

  static Future<void> insertQrSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert(tableQrSessions, session, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getQrSession(String id) async {
    final db = await database;
    final rows = await db.query(
      tableQrSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<Map<String, dynamic>?> getActiveQrSession(String teacherId) async {
    final db = await database;
    final rows = await db.query(
      tableQrSessions,
      where: 'teacher_id = ? AND is_active = 1',
      whereArgs: [teacherId],
      limit: 1,
      orderBy: 'created_at DESC',
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<void> updateQrSessionToken(String id, String token, String tokenCreatedAt) async {
    final db = await database;
    await db.update(
      tableQrSessions,
      {'current_token': token, 'token_created_at': tokenCreatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> closeQrSession(String id) async {
    final db = await database;
    await db.update(
      tableQrSessions,
      {'is_active': 0, 'closed_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedQrSessions() async {
    final db = await database;
    return db.query(
      tableQrSessions,
      where: "sync_status IN ('pending', 'failed')",
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> markQrSessionSynced(String id) async {
    final db = await database;
    await db.update(
      tableQrSessions,
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark all attendance records for a QR session as pending sync.
  /// Called when creating a session offline — so existing records from a
  /// previous online session don't get re-synced.
  static Future<void> markQrAttendancePending(String sessionId) async {
    final db = await database;
    await db.update(
      tableAttendanceLocal,
      {'sync_status': 'pending'},
      where: 'session_id = ? AND sync_status = ?',
      whereArgs: [sessionId, 'synced'],
    );
  }

  static Future<int> getQrPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $tableQrSessions WHERE sync_status IN ('pending', 'failed')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete a QR session and associated attendance records.
  static Future<void> deleteQrSession(String id) async {
    final db = await database;
    await db.delete(tableQrSessions, where: 'id = ?', whereArgs: [id]);
    await db.delete(
      tableAttendanceLocal,
      where: 'session_id = ?',
      whereArgs: [id],
    );
  }
}
