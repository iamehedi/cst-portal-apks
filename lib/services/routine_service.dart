import 'dart:async';

import 'supabase_service.dart';

/// Single canonical model for a class routine slot — used by admin, student, and teacher.
class ClassRoutine {
  final String id;
  final int semester;
  final String day;
  final int periodIndex;
  final String subject;
  final String? subjectCode;
  final String? teacher;
  final String? acronym;
  final String? room;

  const ClassRoutine({
    required this.id,
    required this.semester,
    required this.day,
    required this.periodIndex,
    required this.subject,
    this.subjectCode,
    this.teacher,
    this.acronym,
    this.room,
  });

  String get slotKey => '$semester|$day|$periodIndex';

  factory ClassRoutine.fromRow(Map<String, dynamic> row) {
    return ClassRoutine(
      id: row['id']?.toString() ?? '',
      semester: RoutineService.parseSemester(row['semester']),
      day: RoutineService.normalizeDay(row['day']?.toString()),
      periodIndex: int.tryParse(row['period_index']?.toString() ?? '') ?? 0,
      subject: row['subject']?.toString() ?? '',
      subjectCode: _optionalString(row['subject_code']),
      teacher: _optionalString(row['teacher']),
      acronym: _optionalString(row['acronym']),
      room: _optionalString(row['room']),
    );
  }

  static String? _optionalString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Map<String, dynamic> toRow({bool includeId = true}) {
    return {
      if (includeId && id.isNotEmpty) 'id': id,
      'semester': semester,
      'day': day,
      'period_index': periodIndex,
      'subject': subject,
      'subject_code': subjectCode,
      'teacher': teacher,
      'acronym': acronym,
      'room': room,
    };
  }

  /// Legacy shape still used by [ReminderService].
  Map<String, dynamic> toReminderMap() => {
        'day': day,
        'period_index': periodIndex,
        'subject': subject,
        'subject_code': subjectCode,
        'teacher': teacher,
        'room': room,
        'semester': semester,
      };

  ClassRoutine copyWith({
    String? id,
    int? semester,
    String? day,
    int? periodIndex,
    String? subject,
    String? subjectCode,
    String? teacher,
    String? acronym,
    String? room,
  }) {
    return ClassRoutine(
      id: id ?? this.id,
      semester: semester ?? this.semester,
      day: day ?? this.day,
      periodIndex: periodIndex ?? this.periodIndex,
      subject: subject ?? this.subject,
      subjectCode: subjectCode ?? this.subjectCode,
      teacher: teacher ?? this.teacher,
      acronym: acronym ?? this.acronym,
      room: room ?? this.room,
    );
  }
}

/// One data layer for class routines — every screen reads/writes through here.
class RoutineService {
  static const _table = 'class_routine_slots';

  /// Sentinel value: show every semester (admin only in UI).
  static const int allSemesters = 0;

  static const int defaultSemester = 3;

  static bool isAllSemesters(int semester) => semester == allSemesters;

  static int importTargetSemester(int selectedSemester) =>
      isAllSemesters(selectedSemester) ? defaultSemester : selectedSemester;

  /// Number of standard 45-minute periods (indices 0–6).
  static const int regularPeriodCount = 7;

  static const days = ['SUN', 'MON', 'TUE', 'WED', 'THU'];
  static const dayLabels = {
    'SUN': 'Sunday',
    'MON': 'Monday',
    'TUE': 'Tuesday',
    'WED': 'Wednesday',
    'THU': 'Thursday',
  };
  static const periodTimes = [
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

  static int parseSemester(dynamic value) {
    if (value is int && value >= 1 && value <= 8) return value;
    final fromLabel = SupabaseService.semesterToInt(value?.toString());
    if (fromLabel != null && fromLabel >= 1 && fromLabel <= 8) return fromLabel;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed >= 1 && parsed <= 8) return parsed;
    return 1;
  }

  static int profileSemester(Map<String, dynamic>? profile) =>
      parseSemester(profile?['semester']);

  static String normalizeDay(String? day) {
    final upper = (day ?? 'SUN').trim().toUpperCase();
    const aliases = {
      'SUNDAY': 'SUN',
      'MONDAY': 'MON',
      'TUESDAY': 'TUE',
      'TUES': 'TUE',
      'WEDNESDAY': 'WED',
      'THURSDAY': 'THU',
      'THURS': 'THU',
    };
    final normalized = aliases[upper] ?? (upper.length >= 3 ? upper.substring(0, 3) : upper);
    return days.contains(normalized) ? normalized : 'SUN';
  }

  /// Live updates from the single `class_routine_slots` table.
  /// All roles subscribe the same way, then filter to one semester.
  static Stream<List<ClassRoutine>> watch(int semester) {
    return SupabaseService.client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('semester')
        .order('day')
        .order('period_index')
        .map((rows) => forSemester(rows, semester));
  }

  static Future<List<ClassRoutine>> fetch(int semester) async {
    final rows = await SupabaseService.client
        .from(_table)
        .select()
        .order('semester')
        .order('day')
        .order('period_index');
    return forSemester(rows, semester);
  }

  /// Shared filter + dedupe so admin and student always see identical data for a semester.
  static List<ClassRoutine> forSemester(
    List<Map<String, dynamic>> rows,
    int semester,
  ) {
    final deduped = <String, ClassRoutine>{};
    for (final row in rows) {
      final slot = ClassRoutine.fromRow(row);
      if (!isAllSemesters(semester) && slot.semester != semester) continue;
      deduped[slot.slotKey] = slot;
    }

    final list = deduped.values.toList();
    list.sort((a, b) {
      final semCmp = a.semester.compareTo(b.semester);
      if (semCmp != 0) return semCmp;
      final dayCmp = days.indexOf(a.day).compareTo(days.indexOf(b.day));
      if (dayCmp != 0) return dayCmp;
      return a.periodIndex.compareTo(b.periodIndex);
    });
    return list;
  }

  static List<ClassRoutine> search(List<ClassRoutine> slots, String query) {
    if (query.trim().isEmpty) return slots;
    final q = query.trim().toLowerCase();
    return slots.where((slot) {
      return slot.subject.toLowerCase().contains(q) ||
          (slot.subjectCode ?? '').toLowerCase().contains(q) ||
          (slot.teacher ?? '').toLowerCase().contains(q) ||
          (slot.room ?? '').toLowerCase().contains(q) ||
          (slot.acronym ?? '').toLowerCase().contains(q);
    }).toList();
  }

  static Map<String, List<ClassRoutine>> groupByDay(List<ClassRoutine> slots) {
    final map = <String, List<ClassRoutine>>{};
    for (final day in days) {
      map[day] = slots.where((slot) => slot.day == day).toList();
    }
    return map;
  }

  static Future<void> save(ClassRoutine slot) async {
    final payload = slot.toRow(includeId: false);
    payload['day'] = normalizeDay(payload['day']?.toString());
    payload['semester'] = parseSemester(payload['semester']);

    if (slot.id.isNotEmpty) {
      await SupabaseService.client.from(_table).update(payload).eq('id', slot.id);
      return;
    }

    await SupabaseService.client.from(_table).upsert(
      payload,
      onConflict: 'semester,day,period_index',
    );
  }

  static Future<int> importBulk(List<Map<String, dynamic>> rows, int semester) async {
    final sem = parseSemester(semester);

    // Upsert each record individually so a single failure doesn't wipe data.
    // Batch upsert with composite onConflict is unreliable in supabase_flutter 2.x,
    // so we do one-at-a-time upserts — each handles conflicts by updating the row.
    final errors = <String>[];
    int succeeded = 0;

    for (final row in rows) {
      try {
        final payload = {
          ...row,
          'semester': sem,
          'day': normalizeDay(row['day']?.toString()),
          'period_index': int.tryParse(row['period_index']?.toString() ?? '') ?? 0,
        };
        await SupabaseService.client.from(_table).upsert(
          payload,
          onConflict: 'semester,day,period_index',
        );
        succeeded++;
      } catch (e) {
        errors.add(friendlyErrorMessage(e));
      }
    }

    if (errors.isNotEmpty) {
      final summary = errors.take(3).join('; ');
      if (succeeded == 0) {
        throw Exception('All ${rows.length} records failed. $summary');
      }
      // Partial success — report it so the caller can show accurate info.
      throw Exception(
        'Imported $succeeded/${rows.length} classes, ${errors.length} failed. $summary',
      );
    }

    return succeeded;
  }

  /// Extracts user-friendly message from a Supabase/PostgREST error.
  static String friendlyErrorMessage(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('409') ||
        msg.contains('duplicate') ||
        msg.contains('already exists')) {
      // This shouldn't happen with individual upserts + onConflict,
      // but handle it gracefully just in case.
      return 'duplicate entry (will be updated on retry)';
    }
    if (msg.contains('rls') ||
        msg.contains('row-level security') ||
        msg.contains('permission denied') ||
        msg.contains('403')) {
      return 'permission denied — admin access required';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'request timed out';
    }
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network')) {
      return 'network error';
    }
    final text = error.toString().replaceAll(RegExp(r'^Exception: '), '');
    return text.length > 80 ? text.substring(0, 80) : text;
  }

  static Future<void> delete(String id) =>
      SupabaseService.client.from(_table).delete().eq('id', id);

  /// Removes every routine row except the given semester (admin RLS required).
  static Future<int> deleteExceptSemester(int semester) async {
    final rows = await SupabaseService.client
        .from(_table)
        .delete()
        .neq('semester', semester)
        .select('id');
    return rows.length;
  }

  static Future<List<int>> availableSemesters() async {
    final rows = await SupabaseService.client.from(_table).select('semester');
    final semesters = rows.map((r) => parseSemester(r['semester'])).toSet().toList();
    semesters.sort();
    return semesters;
  }
}
