import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class CsvExport {
  /// Generate a CSV string from attendance records and stats.
  static String generateAttendanceCsv({
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> stats,
  }) {
    final buf = StringBuffer();

    // Header
    buf.writeln('Student ID,Name,Department,Subject,Date,Time,Method,Attendance %');

    // Build stats lookup: "studentId|subject|semester" → percentage
    final statsMap = <String, int>{};
    for (final s in stats) {
      final key = '${s['student_id']}|${s['subject']}|${s['semester']}';
      statsMap[key] = s['percentage'] as int;
    }

    // Data rows
    for (final r in records) {
      final session = r['attendance_sessions'] as Map<String, dynamic>?;
      final studentId = _escape(r['student_id']?.toString() ?? '');
      final studentName = _escape(r['student_name']?.toString() ?? '');
      final dept = _escape(session?['department']?.toString() ?? 'CST');
      final subj = _escape(session?['subject']?.toString() ?? '');
      final sem = session?['semester']?.toString() ?? '';
      final markedAt = r['marked_at']?.toString() ?? '';
      final method = (r['method']?.toString() ?? '').toUpperCase();

      String date = '';
      String time = '';
      if (markedAt.isNotEmpty) {
        try {
          final dt = DateTime.parse(markedAt).toLocal();
          date = DateFormat('yyyy-MM-dd').format(dt);
          time = DateFormat('HH:mm:ss').format(dt);
        } catch (_) {
          date = markedAt;
        }
      }

      final key = '${r['student_id']}|$subj|$sem';
      final pct = statsMap[key]?.toString() ?? '';

      buf.writeln('$studentId,$studentName,$dept,$subj,$date,$time,$method,$pct');
    }

    return buf.toString();
  }

  /// Escape a CSV field — wrap in quotes if it contains commas, quotes, or newlines.
  static String _escape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Generate a CSV string from student list data.
  /// Handles both registered profiles and legacy students table entries.
  static String generateStudentCsv(List<Map<String, dynamic>> students) {
    final buf = StringBuffer();

    // Header row
    buf.writeln('Name,Email,Roll,Registration,Shift,Session,Contact,Source');

    for (final s in students) {
      final name = _escape(s['name']?.toString() ?? '');
      final email = _escape(s['email']?.toString() ?? '');
      final roll = _escape(s['roll']?.toString() ?? '');
      final reg = _escape(s['registration']?.toString() ?? '');
      final shift = _escape(s['shift']?.toString() ?? '');
      final session = _escape(s['session']?.toString() ?? '');
      final contact = _escape(s['contact']?.toString() ?? '');
      final source = s['_source'] == 'profile' ? 'Registered' : 'Legacy';

      buf.writeln('$name,$email,$roll,$reg,$shift,$session,$contact,$source');
    }

    return buf.toString();
  }

  /// Save CSV content to a file using Dart I/O + path_provider.
  /// Works on all platforms without native MethodChannel code.
  /// Returns the saved file path.
  static Future<String> saveCsvToDownloads(String csvContent, {String? fileName}) async {
    final dateStr = DateFormat('dd_MMM_yyyy').format(DateTime.now());
    final name = fileName ?? 'CST_Students_$dateStr.csv';

    // Use app documents directory — writable on all platforms
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(csvContent);
    return file.path;
  }
}
