import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';

import 'routine_service.dart';

/// One routine row in API-ready JSON.
class RoutineJsonEntry {
  final String id;
  final String subjectCode;
  final String teacherName;
  final String teacherAcronym;
  final String day;
  final String time;
  final String title;
  final String description;

  const RoutineJsonEntry({
    required this.id,
    required this.subjectCode,
    this.teacherName = '',
    this.teacherAcronym = '',
    required this.day,
    required this.time,
    required this.title,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_code': subjectCode,
        'teacher_name': teacherName,
        'teacher_acronym': teacherAcronym,
        'day': day,
        'time': time,
        'title': title,
        'description': description,
      };

  /// Convert to Supabase slot for in-app import.
  RoutineImportSlot toImportSlot() => RoutineImportSlot(
        day: RoutineService.normalizeDay(day),
        periodIndex: RoutineJsonParser.periodIndexFromTime(time),
        subject: title,
        subjectCode: subjectCode,
        teacher: teacherName.isNotEmpty ? teacherName : teacherAcronym,
        acronym: teacherAcronym,
        room: description,
      );
}

class SkippedRecord {
  final int row;
  final String reason;
  final Map<String, String> raw;

  const SkippedRecord({
    required this.row,
    required this.reason,
    this.raw = const {},
  });

  Map<String, dynamic> toJson() => {
        'row': row,
        'reason': reason,
        if (raw.isNotEmpty) 'raw': raw,
      };
}

/// Full payload for API deployment.
class RoutineSchedulePayload {
  final DateTime lastUpdated;
  final List<RoutineJsonEntry> routines;
  final List<SkippedRecord> skippedRecords;

  const RoutineSchedulePayload({
    required this.lastUpdated,
    required this.routines,
    this.skippedRecords = const [],
  });

  Map<String, dynamic> toJson() => {
        'last_updated': lastUpdated.toUtc().toIso8601String(),
        'routines': routines.map((r) => r.toJson()).toList(),
        if (skippedRecords.isNotEmpty)
          'skipped_records': skippedRecords.map((s) => s.toJson()).toList(),
      };

  String toJsonString({bool pretty = false}) {
    if (pretty) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(toJson());
    }
    return jsonEncode(toJson());
  }

  List<RoutineImportSlot> toImportSlots() =>
      routines.map((r) => r.toImportSlot()).toList();
}

/// Slot shape used by [RoutineImportService] after JSON normalization.
class RoutineImportSlot {
  final String day;
  final int periodIndex;
  final String subject;
  final String subjectCode;
  final String teacher;
  final String acronym;
  final String room;

  RoutineImportSlot({
    required this.day,
    required this.periodIndex,
    required this.subject,
    this.subjectCode = '',
    this.teacher = '',
    this.acronym = '',
    this.room = '',
  });

  Map<String, dynamic> toMap(int semester) => {
        'semester': semester,
        'day': RoutineService.normalizeDay(day),
        'period_index': periodIndex,
        'subject': subject,
        'subject_code': subjectCode,
        'teacher': teacher,
        'acronym': acronym,
        'room': room,
      };
}

/// Parses CSV / table uploads into clean JSON for the Flutter app and APIs.
class RoutineJsonParser {
  static const _dayDisplay = {
    'SUN': 'Sunday',
    'MON': 'Monday',
    'TUE': 'Tuesday',
    'WED': 'Wednesday',
    'THU': 'Thursday',
    'FRI': 'Friday',
    'SAT': 'Saturday',
  };

  static const _subjectCodeHeaders = [
    'subject code',
    'subject_code',
    'code',
    'course code',
    'paper code',
    'paper',
  ];
  static const _acronymHeaders = [
    'teacher acronym',
    'teacher_acronym',
    'acronym',
    'teacher short',
    'instructor acronym',
  ];
  static const _dayHeaders = ['day', 'weekday', 'day of week'];
  static const _timeHeaders = [
    'time',
    'period',
    'period time',
    'class time',
    'slot',
    'schedule',
  ];
  static const _titleHeaders = [
    'title',
    'subject name',
    'name of the subject',
    'name',
    'course',
    'paper name',
  ];
  static const _descriptionHeaders = [
    'description',
    'room',
    'classroom',
    'venue',
    'details',
    'location',
    'room number',
  ];
  static const _teacherNameHeaders = [
    'teacher',
    'teacher name',
    'instructor',
    'faculty',
    'name of the teacher',
  ];

  static Future<RoutineSchedulePayload> parseFile(String path, Uint8List bytes) async {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'csv':
        return _parseCsv(bytes);
      case 'docx':
        return _parseDocx(bytes);
      default:
        throw const FormatException('Unsupported file format. Use .csv or .docx');
    }
  }

  static RoutineSchedulePayload _parseCsv(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final rows = const CsvDecoder().convert(content);
    if (rows.isEmpty) {
      throw const FormatException('File is empty');
    }

    final headerIdx = _findHeaderRow(rows);
    final headers = rows[headerIdx].map((c) => _cleanCell(c)).toList();
    final headerLower = headers.map((h) => h.toLowerCase()).toList();

    final codeCol = _findColumn(headerLower, _subjectCodeHeaders);
    final acronymCol = _findColumn(headerLower, _acronymHeaders);
    final teacherNameCol = _findColumn(headerLower, _teacherNameHeaders);
    final dayCol = _findColumn(headerLower, _dayHeaders);
    final timeCol = _findColumn(headerLower, _timeHeaders);
    var titleCol = _findColumn(headerLower, _titleHeaders);
    // Fallback: bare "Subject" header (without "code") — exact match only
    if (titleCol < 0) {
      for (var i = 0; i < headerLower.length; i++) {
        if (headerLower[i] == 'subject' && i != codeCol) {
          titleCol = i;
          break;
        }
      }
    }
    final descCol = _findColumn(headerLower, _descriptionHeaders);

    if (codeCol == -1 && titleCol == -1) {
      throw FormatException(
        'Could not find Subject Code or Title column. Headers: ${headers.join(", ")}',
      );
    }

    final routines = <RoutineJsonEntry>[];
    final skipped = <SkippedRecord>[];
    var seq = 1;

    for (var i = headerIdx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (_rowEmpty(row)) continue;

      final raw = _rowAsMap(headers, row);
      final subjectCode = _upper(codeCol >= 0 ? _cell(row, codeCol) : '');
      final dayRaw = dayCol >= 0 ? _cell(row, dayCol) : '';
      final timeRaw = timeCol >= 0 ? _cell(row, timeCol) : '';
      final title = titleCol >= 0 ? _cell(row, titleCol) : '';
      final description = descCol >= 0 ? _cell(row, descCol) : '';

      // Teacher info: detect acronym and/or full name columns independently
      final acronym = acronymCol >= 0 ? _upper(_cell(row, acronymCol)) : '';
      final teacherName = teacherNameCol >= 0 ? _cell(row, teacherNameCol) : '';

      final dayNorm = _normalizeDayToken(dayRaw);
      final dayDisplay = _dayDisplay[dayNorm] ?? dayRaw;
      final time = _resolveTimeString(timeRaw);

      final missing = <String>[];
      if (subjectCode.isEmpty) missing.add('subject_code');
      if (dayNorm.isEmpty) missing.add('day');
      if (time.isEmpty) missing.add('time');

      if (missing.isNotEmpty) {
        skipped.add(SkippedRecord(
          row: i + 1,
          reason: 'Missing required field(s): ${missing.join(", ")}',
          raw: raw,
        ));
        continue;
      }

      routines.add(RoutineJsonEntry(
        id: seq.toString(),
        subjectCode: subjectCode,
        teacherName: teacherName,
        teacherAcronym: acronym,
        day: dayDisplay,
        time: time,
        title: title.isNotEmpty ? title : subjectCode,
        description: description,
      ));
      seq++;
    }

    return RoutineSchedulePayload(
      lastUpdated: DateTime.now().toUtc(),
      routines: routines,
      skippedRecords: skipped,
    );
  }

  static RoutineSchedulePayload _parseDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? docFile;
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        docFile = file;
        break;
      }
    }
    if (docFile == null) {
      throw const FormatException('Invalid DOCX: no document.xml found');
    }

    final xmlContent = String.fromCharCodes(docFile.content as List<int>);
    final xmlDoc = XmlDocument.parse(xmlContent);

    final tables = <XmlElement>[];
    for (final el in xmlDoc.descendants) {
      if (el is XmlElement && el.name.local == 'tbl') tables.add(el);
    }
    if (tables.isEmpty) {
      throw const FormatException('No tables found in the document');
    }

    final subjectLookup = <String, Map<String, String>>{};
    final flatRows = <List<String>>[];

    for (final table in tables) {
      final rows = _docxRows(table);
      if (rows.isEmpty) continue;

      final headerCells = rows.first.map(_cleanCell).toList();
      final headerStr = headerCells.join(' ').toLowerCase();

      if (headerStr.contains('subject code') && headerStr.contains('name')) {
        final headerLower = headerCells.map((h) => h.toLowerCase()).toList();
        final codeCol = _findColumn(headerLower, _subjectCodeHeaders);
        final titleCol = _findColumn(headerLower, _titleHeaders);
        final teacherCol = _findColumn(headerLower, _teacherNameHeaders);
        final acronymCol = _findColumn(headerLower, _acronymHeaders);

        for (var i = 1; i < rows.length; i++) {
          final cells = rows[i].map(_cleanCell).toList();
          if (cells.every((c) => c.isEmpty)) continue;
          final code = _upper(codeCol >= 0 && codeCol < cells.length ? cells[codeCol] : '');
          if (code.isEmpty) continue;
          subjectLookup[code] = {
            'title': titleCol >= 0 && titleCol < cells.length ? cells[titleCol] : '',
            'teacher': teacherCol >= 0 && teacherCol < cells.length ? cells[teacherCol] : '',
            'acronym': acronymCol >= 0 && acronymCol < cells.length ? cells[acronymCol] : '',
          };
        }
        continue;
      }

      if (headerStr.contains('period') || headerStr.contains('time')) {
        final periodHeaders = rows.first.map(_cleanCell).toList();
        final periodCount = periodHeaders.length - 1;

        var dataStart = 1;
        if (rows.length > 1) {
          final timeRow = rows[1].map(_cleanCell).toList();
          if (timeRow.length > 1 && RegExp(r'\d{1,2}:\d{2}').hasMatch(timeRow[1])) {
            for (var p = 1; p < timeRow.length && p <= periodCount; p++) {
              flatRows.add([
                '',
                timeRow[p],
                '',
                '',
                periodHeaders.length > p ? periodHeaders[p] : '$p',
              ]);
            }
            dataStart = 2;
          }
        }

        for (var r = dataStart; r < rows.length; r++) {
          final cells = rows[r].map(_cleanCell).toList();
          if (cells.isEmpty) continue;
          final dayToken = _normalizeDayToken(cells[0]);
          if (dayToken.isEmpty) continue;

          for (var p = 0; p < periodCount && (p + 1) < cells.length; p++) {
            final cellText = cells[p + 1];
            if (cellText.isEmpty) continue;

            final parts = cellText.split(RegExp(r'\s+'));
            final code = _upper(parts.isNotEmpty ? parts[0] : '');
            final acronym = parts.length > 1 ? _upper(parts[1]) : '';
            final room = parts.length > 2 ? parts.sublist(2).join(' ') : '';

            final lookup = subjectLookup[code];
            final timeLabel = p < RoutineService.periodTimes.length
                ? RoutineService.periodTimes[p]
                : 'Period ${p + 1}';

            flatRows.add([
              code,
              acronym.isNotEmpty ? acronym : _upper(lookup?['acronym'] ?? lookup?['teacher'] ?? ''),
              _dayDisplay[dayToken] ?? cells[0],
              timeLabel,
              lookup?['title'] ?? code,
              room.isNotEmpty ? room : '',
            ]);
          }
        }
      }
    }

    if (flatRows.isEmpty) {
      throw const FormatException(
        'No valid routine table found. Expected Subject Code / Day / Time columns or a period grid.',
      );
    }

    return _parseFlatRows(flatRows);
  }

  static RoutineSchedulePayload _parseFlatRows(List<List<String>> rows) {
    final routines = <RoutineJsonEntry>[];
    final skipped = <SkippedRecord>[];
    var seq = 1;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final subjectCode = _upper(row.isNotEmpty ? row[0] : '');
      final acronym = row.length > 1 ? _upper(row[1]) : '';
      final dayRaw = row.length > 2 ? row[2] : '';
      final timeRaw = row.length > 3 ? row[3] : '';
      final title = row.length > 4 ? _cleanCell(row[4]) : '';
      final description = row.length > 5 ? _cleanCell(row[5]) : '';

      final dayNorm = _normalizeDayToken(dayRaw);
      final dayDisplay = _dayDisplay[dayNorm] ?? dayRaw;
      final time = _resolveTimeString(timeRaw);

      final missing = <String>[];
      if (subjectCode.isEmpty) missing.add('subject_code');
      if (dayNorm.isEmpty && dayRaw.isEmpty) missing.add('day');
      if (time.isEmpty) missing.add('time');

      if (missing.isNotEmpty) {
        skipped.add(SkippedRecord(
          row: i + 1,
          reason: 'Missing required field(s): ${missing.join(", ")}',
          raw: {
            'subject_code': subjectCode,
            'day': dayRaw,
            'time': timeRaw,
          },
        ));
        continue;
      }

      routines.add(RoutineJsonEntry(
        id: seq.toString(),
        subjectCode: subjectCode,
        teacherName: acronym, // In flat rows from DOCX, 2nd col is usually acronym
        teacherAcronym: acronym,
        day: dayDisplay.isNotEmpty ? dayDisplay : dayRaw,
        time: time,
        title: title.isNotEmpty ? title : subjectCode,
        description: description,
      ));
      seq++;
    }

    return RoutineSchedulePayload(
      lastUpdated: DateTime.now().toUtc(),
      routines: routines,
      skippedRecords: skipped,
    );
  }

  static int periodIndexFromTime(String time) {
    final cleaned = _cleanCell(time);

    // 1. Exact match against known period times (including combined periods with (2h 15m) suffix)
    for (var i = 0; i < RoutineService.periodTimes.length; i++) {
      if (RoutineService.periodTimes[i] == cleaned) return i;
    }

    // 2. Check for time ranges (e.g., "1:30 – 2:15 PM" or "1:30 - 2:15 PM")
    final rangeMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*(?:–|-|to)\s*(\d{1,2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (rangeMatch != null) {
      final startH = int.parse(rangeMatch.group(1)!);
      final startM = int.parse(rangeMatch.group(2)!);
      final endH = int.parse(rangeMatch.group(3)!);
      final endM = int.parse(rangeMatch.group(4)!);

      // Normalize PM times (all class times are in the afternoon)
      final sMin = (startH < 7 ? startH + 12 : startH) * 60 + startM;
      final eMin = (endH < 7 ? endH + 12 : endH) * 60 + endM;
      final dur = eMin - sMin;

      // Map 135-minute combined periods first (indices 7-11)
      if (dur == 135) {
        const combinedStarts = [810, 855, 900, 945, 990];
        for (var i = combinedStarts.length - 1; i >= 0; i--) {
          if (sMin >= combinedStarts[i]) return i + RoutineService.regularPeriodCount;
        }
      }

      // Map ALL time ranges by start time to the correct period index (0-6 for 45-min, 7-11 for combined)
      // Afternoon minutes since midnight: 1:30 PM = 810, 2:15 = 855, 3:00 = 900, 3:45 = 945,
      // 4:30 = 990, 5:15 = 1035, 6:00 = 1080
      const periodStarts = [810, 855, 900, 945, 990, 1035, 1080];
      for (var i = periodStarts.length - 1; i >= 0; i--) {
        if (sMin >= periodStarts[i]) return i;
      }
    }

    // 3. Integer parse (e.g., "0", "3")
    final direct = int.tryParse(cleaned);
    if (direct != null) return direct;

    // 4. "Period X" pattern (e.g., "period 3", "p 5")
    final periodMatch =
        RegExp(r'(?:period|p)\s*(\d+)', caseSensitive: false).firstMatch(cleaned);
    if (periodMatch != null) {
      final num = int.parse(periodMatch.group(1)!);
      return num > 0 ? num - 1 : 0;
    }

    // 5. Single time (e.g., "1:30", "14:15") — map to the nearest earlier period
    final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(cleaned);
    if (timeMatch != null) {
      final hour = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2)!);
      // Adjust for PM (all class times are in the afternoon; hours 1-6 are PM)
      final adjustedHour = hour < 7 ? hour + 12 : hour;
      final minutes = adjustedHour * 60 + minute;
      const starts = [810, 855, 900, 945, 990, 1035, 1080];
      for (var i = starts.length - 1; i >= 0; i--) {
        if (minutes >= starts[i]) return i;
      }
    }

    return 0;
  }

  static int _findHeaderRow(List<List<dynamic>> rows) {
    for (var i = 0; i < rows.length && i < 15; i++) {
      final joined = rows[i].map((c) => c.toString().toLowerCase()).join(' ');
      if (joined.contains('subject') ||
          joined.contains('day') ||
          joined.contains('time') ||
          joined.contains('code')) {
        return i;
      }
    }
    return 0;
  }

  static int _findColumn(List<String> headers, List<String> keywords) {
    for (var i = 0; i < headers.length; i++) {
      for (final kw in keywords) {
        if (headers[i].contains(kw)) return i;
      }
    }
    return -1;
  }

  static String _cell(List<dynamic> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return _cleanCell(row[col]);
  }

  static String _cleanCell(dynamic value) {
    return value
        .toString()
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _upper(String value) => _cleanCell(value).toUpperCase();

  static bool _rowEmpty(List<dynamic> row) =>
      row.every((c) => _cleanCell(c).isEmpty);

  static Map<String, String> _rowAsMap(List<String> headers, List<dynamic> row) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      final val = _cleanCell(row[i]);
      if (val.isNotEmpty) map[headers[i]] = val;
    }
    return map;
  }

  static String _normalizeDayToken(String raw) {
    final cleaned = _cleanCell(raw).toUpperCase();
    const aliases = {
      'SUNDAY': 'SUN',
      'SUN': 'SUN',
      'MONDAY': 'MON',
      'MON': 'MON',
      'TUESDAY': 'TUE',
      'TUE': 'TUE',
      'TUES': 'TUE',
      'WEDNESDAY': 'WED',
      'WED': 'WED',
      'THURSDAY': 'THU',
      'THU': 'THU',
      'THURS': 'THU',
      'FRIDAY': 'FRI',
      'FRI': 'FRI',
      'SATURDAY': 'SAT',
      'SAT': 'SAT',
    };
    return aliases[cleaned] ?? '';
  }

  static String _resolveTimeString(String raw) {
    final cleaned = _cleanCell(raw);
    if (cleaned.isEmpty) return '';

    if (RegExp(r'\d{1,2}:\d{2}').hasMatch(cleaned) || cleaned.contains('–') || cleaned.contains('-')) {
      return cleaned;
    }

    final idx = periodIndexFromTime(cleaned);
    if (idx >= 0 && idx < RoutineService.periodTimes.length) {
      return RoutineService.periodTimes[idx];
    }

    return cleaned;
  }

  static List<List<String>> _docxRows(XmlElement table) {
    final rows = <List<String>>[];
    for (final el in table.childElements) {
      if (el.name.local != 'tr') continue;
      final cells = <String>[];
      for (final child in el.children) {
        if (child is! XmlElement || child.name.local != 'tc') continue;
        final texts = <String>[];
        for (final d in child.descendants) {
          if (d is XmlElement && d.name.local == 't') texts.add(d.innerText);
        }
        cells.add(_cleanCell(texts.join(' ')));
      }
      rows.add(cells);
    }
    return rows;
  }
}

/// Backward-compatible wrapper for the Flutter import UI.
class RoutineImportResult {
  final List<RoutineImportSlot> slots;
  final List<String> warnings;
  final String? error;
  final RoutineSchedulePayload? payload;

  RoutineImportResult({
    required this.slots,
    this.warnings = const [],
    this.error,
    this.payload,
  });
}

/// Legacy alias — use [RoutineImportSlot].
typedef RoutineSlot = RoutineImportSlot;

class RoutineImportService {
  static Future<RoutineImportResult> parseFile(String path, Uint8List bytes) async {
    try {
      final payload = await RoutineJsonParser.parseFile(path, bytes);
      final warnings = payload.skippedRecords
          .map((s) => 'Row ${s.row}: ${s.reason}')
          .toList();

      if (payload.routines.isEmpty) {
        return RoutineImportResult(
          slots: [],
          warnings: warnings,
          error: warnings.isEmpty
              ? 'No valid routine rows found in file'
              : 'All rows were skipped. Check column headers and required fields.',
          payload: payload,
        );
      }

      return RoutineImportResult(
        slots: payload.toImportSlots(),
        warnings: warnings,
        payload: payload,
      );
    } on FormatException catch (e) {
      return RoutineImportResult(slots: [], error: e.message);
    } catch (e) {
      return RoutineImportResult(slots: [], error: 'Failed to parse file: $e');
    }
  }

  /// Returns API-ready JSON string (no markdown wrappers).
  static Future<String> parseFileToJson(String path, Uint8List bytes) async {
    final payload = await RoutineJsonParser.parseFile(path, bytes);
    return payload.toJsonString();
  }
}
