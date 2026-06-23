import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfExport {
  /// Generate an attendance report PDF from records and stats.
  /// Uses built-in Helvetica fonts (works offline).
  static Future<Uint8List> generateAttendancePdf({
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> stats,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final pdf = pw.Document();

    // Use built-in fonts — no network required, works offline
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    // Build stats lookup: studentId|subject|semester → percentage
    final statsMap = <String, int>{};
    for (final s in stats) {
      final key = '${s['student_id']}|${s['subject']}|${s['semester']}';
      statsMap[key] = s['percentage'] as int;
    }

    final totalRecords = records.length;
    final totalSessions = stats.isEmpty
        ? 0
        : stats
            .map((s) => s['total_sessions'] as int? ?? 0)
            .fold(0, (a, b) => a > b ? a : b);
    final belowThresholdCount =
        stats.where((s) => (s['percentage'] as int? ?? 100) < 75).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(context, font, fontBold),
        footer: (context) => _buildFooter(context, font),
        build: (context) => [
          // ── Title ───────────────────────────────────────────────────────
          pw.Center(
            child: pw.Text(
              'Attendance Report',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 20,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          // Date range filter info
          if (dateFrom != null || dateTo != null) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Date range: ${dateFrom != null ? DateFormat('dd MMM yyyy').format(dateFrom) : 'Any'} → '
                '${dateTo != null ? DateFormat('dd MMM yyyy').format(dateTo) : 'Any'}',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
              ),
            ),
          ],
          pw.Divider(height: 24, thickness: 0.5, color: PdfColors.grey400),

          // ── Summary Cards ───────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _summaryBox(font, fontBold, '$totalRecords', 'Total Records'),
              _summaryBox(font, fontBold, '$totalSessions', 'Sessions'),
              _summaryBox(font, fontBold, '$belowThresholdCount', 'Below 75%'),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Below threshold warning ─────────────────────────────────────
          if (belowThresholdCount > 0) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FFF5F5'),
                border: pw.Border.all(color: PdfColor.fromHex('#FF6B6B')),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'Warning: $belowThresholdCount student(s) below 75% BTEB attendance threshold',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 10,
                  color: PdfColor.fromHex('#CC0000'),
                ),
              ),
            ),
            pw.SizedBox(height: 20),
          ],

          // ── Student-wise Summary Table ──────────────────────────────────
          if (stats.isNotEmpty) ...[
            pw.Text(
              'Student-wise Summary',
              style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.black),
            ),
            pw.SizedBox(height: 6),
            _buildStatsTable(font, fontBold, stats),
            pw.SizedBox(height: 20),
          ],

          // ── All Records ─────────────────────────────────────────────────
          pw.Text(
            'All Attendance Records',
            style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.black),
          ),
          pw.SizedBox(height: 6),
          if (records.isEmpty)
            pw.Center(
              child: pw.Text(
                'No records found.',
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600),
              ),
            )
          else
            ...records.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              final session =
                  r['attendance_sessions'] as Map<String, dynamic>?;
              final subject = session?['subject']?.toString() ?? '';
              final method = (r['method']?.toString() ?? '').toUpperCase();
              final studentId = r['student_id']?.toString() ?? '';
              final studentName = r['student_name']?.toString() ?? '';
              final markedAt = r['marked_at']?.toString() ?? '';

              String time = '';
              if (markedAt.isNotEmpty) {
                try {
                  final dt = DateTime.parse(markedAt).toLocal();
                  time = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
                } catch (_) {
                  time = markedAt;
                }
              }

              final key = '${r['student_id']}|$subject|${session?['semester'] ?? ''}';
              final pct = statsMap[key];
              final belowThreshold = pct != null && pct < 75;

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 3),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: (i % 2 == 0)
                      ? PdfColor.fromHex('#F8F9FA')
                      : PdfColors.white,
                  border: pw.Border.all(
                    color: belowThreshold
                        ? PdfColor.fromHex('#FFCCCC')
                        : PdfColor.fromHex('#E8E8E8'),
                    width: 0.5,
                  ),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            studentName,
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.Text(
                            'ID: $studentId',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 7,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        subject,
                        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        time,
                        style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: pw.BoxDecoration(
                        color: method == 'QR'
                            ? PdfColor.fromHex('#E8F5E9')
                            : PdfColor.fromHex('#FFF3E0'),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(
                        method,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 7,
                          color: method == 'QR'
                              ? PdfColor.fromHex('#2E7D32')
                              : PdfColor.fromHex('#E65100'),
                        ),
                      ),
                    ),
                    if (pct != null) ...[
                      pw.SizedBox(width: 4),
                      pw.Text(
                        '$pct%',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: pct < 75
                              ? PdfColor.fromHex('#CC0000')
                              : PdfColor.fromHex('#2E7D32'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Header/Footer ──────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    pw.Context context,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'CST Portal - Attendance Report',
          style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page ${context.pageNumber}',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(
    pw.Context context,
    pw.Font font,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          'CST Department Portal - Confidential',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400),
        ),
      ],
    );
  }

  // ── Summary Box ────────────────────────────────────────────────────────────

  static pw.Widget _summaryBox(
    pw.Font font,
    pw.Font fontBold,
    String value,
    String label, {
    PdfColor? color,
  }) {
    final valueColor = color ?? PdfColors.black;
    return pw.Container(
      width: 100,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8F9FA'),
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 20,
              color: valueColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ── Stats Table ─────────────────────────────────────────────────────────────

  static pw.Widget _buildStatsTable(
    pw.Font font,
    pw.Font fontBold,
    List<Map<String, dynamic>> stats,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColor.fromHex('#E0E0E0'),
        width: 0.5,
      ),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF333333),
          ),
          children: [
            _cell('ID', fontBold, PdfColors.white, isHeader: true),
            _cell('Name', fontBold, PdfColors.white, isHeader: true),
            _cell('Subject', fontBold, PdfColors.white, isHeader: true),
            _cell('Att / Tot (%)', fontBold, PdfColors.white, isHeader: true),
            _cell('Status', fontBold, PdfColors.white, isHeader: true),
          ],
        ),
        // Data rows
        ...stats.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final pct = s['percentage'] as int? ?? 0;
          final below = pct < 75;
          final attended = s['attended'] as int? ?? 0;
          final total = s['total_sessions'] as int? ?? 0;
          final rowColor = below
              ? PdfColor.fromHex('#FFF5F5')
              : (i % 2 == 0
                  ? PdfColor.fromHex('#F8F9FA')
                  : PdfColors.white);

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowColor),
            children: [
              _cell(s['student_id']?.toString() ?? '', font, PdfColors.black),
              _cell(s['student_name']?.toString() ?? '', font, PdfColors.black),
              _cell(s['subject']?.toString() ?? '', font, PdfColors.black),
              _cell('$attended/$total ($pct%)', fontBold,
                  below ? PdfColor.fromHex('#CC0000') : PdfColors.black),
              _cell(
                below ? 'BELOW 75%' : 'OK',
                fontBold,
                below ? PdfColor.fromHex('#CC0000') : PdfColor.fromHex('#2E7D32'),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _cell(
    String text,
    pw.Font font,
    PdfColor color, {
    bool isHeader = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 8 : 7,
          color: color,
        ),
      ),
    );
  }

  // ── Student Personal Report ────────────────────────────────────────────

  /// Generate a simpler PDF for a single student's own attendance records.
  /// The records are flat (no nested `attendance_sessions`) as returned by
  /// the `get_student_attendance` RPC.
  static Future<Uint8List> generateStudentPdf({
    required String studentName,
    required String studentId,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> stats,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CST Portal - My Attendance',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber}',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
          ],
        ),
        footer: (context) => pw.Center(
          child: pw.Text('CST Department Portal - Confidential',
              style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
        ),
        build: (context) => [
          // ── Title ──
          pw.Center(child: pw.Text('My Attendance Report',
              style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.black))),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(now)}',
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700))),
          pw.Divider(height: 24, thickness: 0.5, color: PdfColors.grey400),

          // ── Student Info ──
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F0F4FF'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: PdfColor.fromHex('#CCCCCC'), width: 0.5),
            ),
            child: pw.Row(
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Student: $studentName',
                      style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.black)),
                  pw.SizedBox(height: 4),
                  pw.Text('ID: $studentId',
                      style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 2),
                  pw.Text('${stats.length} subject(s) \u00b7 ${records.length} total entries',
                      style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Subject-wise Stats ──
          if (stats.isNotEmpty) ...[
            pw.Text('Attendance by Subject',
                style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.black)),
            pw.SizedBox(height: 8),
            ...stats.asMap().entries.map((entry) {
              final s = entry.value;
              final subject = s['subject']?.toString() ?? 'Unknown';
              final attended = s['attended'] as int? ?? 0;
              final total = s['total_sessions'] as int? ?? 0;
              final pct = s['percentage'] as int? ?? 0;
              final below = pct < 75;

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: below ? PdfColor.fromHex('#FFF5F5') : PdfColor.fromHex('#F8F9FA'),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(
                    color: below ? PdfColor.fromHex('#FFCCCC') : PdfColor.fromHex('#E0E0E0'),
                    width: 0.5,
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(subject,
                          style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.black)),
                    ),
                    pw.Text('$attended / $total',
                        style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: below
                            ? PdfColor.fromHex('#FFE0E0')
                            : PdfColor.fromHex('#E8F5E9'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text('$pct%',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: below ? PdfColor.fromHex('#CC0000') : PdfColor.fromHex('#2E7D32'),
                          )),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 16),
          ],

          // ── Recent Records ──
          pw.Text('Attendance Records',
              style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.black)),
          pw.SizedBox(height: 8),
          if (records.isEmpty)
            pw.Center(
              child: pw.Text('No records found.',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            )
          else
            ...records.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              final subject = r['subject']?.toString() ?? '';
              final method = (r['method']?.toString() ?? '').toUpperCase();
              final markedAt = r['marked_at']?.toString() ?? '';

              String time = '';
              if (markedAt.isNotEmpty) {
                try {
                  final dt = DateTime.parse(markedAt).toLocal();
                  time = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
                } catch (_) {
                  time = markedAt;
                }
              }

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: i % 2 == 0 ? PdfColor.fromHex('#F8F9FA') : PdfColors.white,
                  border: pw.Border.all(color: PdfColor.fromHex('#E8E8E8'), width: 0.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(subject,
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.black)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(time,
                          style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: method == 'QR'
                            ? PdfColor.fromHex('#E8F5E9')
                            : PdfColor.fromHex('#FFF3E0'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(method,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7,
                            color: method == 'QR'
                                ? PdfColor.fromHex('#2E7D32')
                                : PdfColor.fromHex('#E65100'),
                          )),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Simple Student List PDF ────────────────────────────────────────────

  /// Generate a simple PDF showing a list of students with name, roll, registration.
  /// [title] is the report heading (e.g. "March 2024" or "Physics").
  /// [students] is a list of maps with 'name', 'roll', 'reg' keys.
  static Future<Uint8List> generateStudentListPdf({
    required String title,
    required String subtitle,
    required List<Map<String, String>> students,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CST Portal - Attendance',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber}',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
          ],
        ),
        footer: (context) => pw.Center(
          child: pw.Text('CST Department Portal - Confidential',
              style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(title,
                style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.black)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(subtitle,
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('${students.length} student(s)',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
          ),
          pw.Divider(height: 20, thickness: 0.5, color: PdfColors.grey400),

          if (students.isEmpty)
            pw.Center(
              child: pw.Text('No students found.',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF333333)),
                  children: [
                    _cell('#', fontBold, PdfColors.white, isHeader: true),
                    _cell('Name', fontBold, PdfColors.white, isHeader: true),
                    _cell('Roll', fontBold, PdfColors.white, isHeader: true),
                    _cell('Registration', fontBold, PdfColors.white, isHeader: true),
                  ],
                ),
                // Body
                for (int i = 0; i < students.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0 ? PdfColor.fromHex('#F8F9FA') : PdfColors.white,
                    ),
                    children: [
                      _cell('${i + 1}', font, PdfColors.black),
                      _cell(students[i]['name'] ?? '', fontBold, PdfColors.black),
                      _cell(students[i]['roll'] ?? '', font, PdfColors.black),
                      _cell(students[i]['reg'] ?? '', font, PdfColors.grey700),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Detailed Attendance Report PDF ────────────────────────────────────

  /// Generate a detailed attendance report with individual record rows.
  /// Shows: #, Student Name, Roll, Reg, Subject, Date/Time, Method.
  /// Uses [records] with nested `attendance_sessions` as returned by
  /// [AttendanceService.getAttendanceReport].
  static Future<Uint8List> generateDetailedReportPdf({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> records,
    required Map<String, String> rollToRegistration,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CST Portal - Attendance Report',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber}',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
          ],
        ),
        footer: (context) => pw.Center(
          child: pw.Text('CST Department Portal - Confidential',
              style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(title,
                style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.black)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(subtitle,
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('${records.length} attendance record(s)',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
          ),
          pw.Divider(height: 20, thickness: 0.5, color: PdfColors.grey400),

          if (records.isEmpty)
            pw.Center(
              child: pw.Text('No records found.',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF333333)),
                  children: [
                    _cell('#', fontBold, PdfColors.white, isHeader: true),
                    _cell('Name', fontBold, PdfColors.white, isHeader: true),
                    _cell('Roll', fontBold, PdfColors.white, isHeader: true),
                    _cell('Reg', fontBold, PdfColors.white, isHeader: true),
                    _cell('Subject', fontBold, PdfColors.white, isHeader: true),
                    _cell('Date/Time', fontBold, PdfColors.white, isHeader: true),
                    _cell('Method', fontBold, PdfColors.white, isHeader: true),
                  ],
                ),
                // Body
                for (int i = 0; i < records.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0 ? PdfColor.fromHex('#F8F9FA') : PdfColors.white,
                    ),
                    children: [
                      _cell('${i + 1}', font, PdfColors.black),
                      _cell(_recordName(records[i]), fontBold, PdfColors.black),
                      _cell(_recordRoll(records[i]), font, PdfColors.black),
                      _cell(_recordReg(records[i], rollToRegistration), font, PdfColors.grey700),
                      _cell(_recordSubject(records[i]), font, PdfColors.black),
                      _cell(_recordDateTime(records[i]), font, PdfColors.grey700),
                      _cell(_recordMethod(records[i]), font,
                          _recordMethodColor(records[i])),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static String _recordName(Map<String, dynamic> r) => r['student_name']?.toString() ?? '';
  static String _recordRoll(Map<String, dynamic> r) => r['student_id']?.toString() ?? '';
  static String _recordReg(Map<String, dynamic> r, Map<String, String> rollToReg) {
    final id = r['student_id']?.toString() ?? '';
    return rollToReg[id] ?? '\u2014';
  }
  static String _recordSubject(Map<String, dynamic> r) {
    final session = r['attendance_sessions'] as Map<String, dynamic>?;
    return session?['subject']?.toString() ?? '';
  }
  static String _recordDateTime(Map<String, dynamic> r) {
    final session = r['attendance_sessions'] as Map<String, dynamic>?;
    final classDate = session?['class_date']?.toString() ?? '';
    final classTime = session?['class_time']?.toString() ?? '';
    if (classDate.isNotEmpty && classTime.isNotEmpty) {
      return '$classDate, $classTime';
    }
    if (classDate.isNotEmpty) return classDate;
    final markedAt = r['marked_at']?.toString() ?? '';
    if (markedAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(markedAt).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return markedAt;
    }
  }
  static String _recordMethod(Map<String, dynamic> r) {
    final method = (r['method']?.toString() ?? '').toUpperCase();
    if (method == 'BLE') {
      final status = r['_ble_status']?.toString() ?? 'present';
      return 'BLE - ${status[0].toUpperCase()}${status.substring(1)}';
    }
    return method;
  }

  static PdfColor _recordMethodColor(Map<String, dynamic> r) {
    final method = (r['method']?.toString() ?? '').toUpperCase();
    if (method != 'BLE') return PdfColor.fromHex('#2E7D32');
    final status = r['_ble_status']?.toString() ?? '';
    switch (status) {
      case 'present':
        return PdfColor.fromHex('#2E7D32');
      case 'rejected':
        return PdfColor.fromHex('#CC0000');
      case 'disconnected':
        return PdfColor.fromHex('#E65100');
      default:
        return PdfColor.fromHex('#FF8F00');
    }
  }

  // ── BLE Session PDF ──────────────────────────────────────────────────────

  /// Generate a PDF report for a BLE attendance session.
  /// Shows session info (subject, semester) and student roster with status.
  static Future<Uint8List> generateBleSessionPdf({
    required String subject,
    required int semester,
    required List<({String studentId, String studentName, String status})> roster,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();
    final now = DateTime.now();

    final present = roster.where((s) => s.status == 'present').length;
    final rejected = roster.where((s) => s.status == 'rejected').length;
    final pending = roster.where((s) => s.status == 'pending' || s.status == 'disconnected').length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CST Portal - Smart Attendance Report',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber}',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
          ],
        ),
        footer: (context) => pw.Center(
          child: pw.Text('CST Department Portal - Confidential',
              style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text('Smart Attendance Report',
                style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.black)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(now)}',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.Divider(height: 20, thickness: 0.5, color: PdfColors.grey400),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _summaryBox(font, fontBold, subject, 'Subject'),
              _summaryBox(font, fontBold, 'Semester $semester', 'Semester'),
            ],
          ),
          pw.SizedBox(height: 20),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _summaryBox(font, fontBold, '${roster.length}', 'Total'),
              _summaryBox(font, fontBold, '$present', 'Present',
                  color: PdfColor.fromHex('#2E7D32')),
              _summaryBox(font, fontBold, '$rejected', 'Rejected',
                  color: PdfColor.fromHex('#CC0000')),
              _summaryBox(font, fontBold, '$pending', 'Pending',
                  color: PdfColor.fromHex('#E65100')),
            ],
          ),
          pw.SizedBox(height: 20),

          pw.Text('Student Roster',
              style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.black)),
          pw.SizedBox(height: 8),

          if (roster.isEmpty)
            pw.Center(
              child: pw.Text('No students found.',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF333333)),
                  children: [
                    _cell('#', fontBold, PdfColors.white, isHeader: true),
                    _cell('Name', fontBold, PdfColors.white, isHeader: true),
                    _cell('ID', fontBold, PdfColors.white, isHeader: true),
                    _cell('Status', fontBold, PdfColors.white, isHeader: true),
                  ],
                ),
                for (int i = 0; i < roster.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0 ? PdfColor.fromHex('#F8F9FA') : PdfColors.white,
                    ),
                    children: [
                      _cell('${i + 1}', font, PdfColors.black),
                      _cell(roster[i].studentName, fontBold, PdfColors.black),
                      _cell(roster[i].studentId, font, PdfColors.black),
                      _cell(
                        _bleStatusLabel(roster[i].status),
                        fontBold,
                        _bleStatusColor(roster[i].status),
                      ),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );
    return pdf.save();
  }

  static String _bleStatusLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'rejected':
        return 'Rejected';
      case 'disconnected':
        return 'Disconnected';
      default:
        return 'Pending';
    }
  }

  static PdfColor _bleStatusColor(String status) {
    switch (status) {
      case 'present':
        return PdfColor.fromHex('#2E7D32');
      case 'rejected':
        return PdfColor.fromHex('#CC0000');
      case 'disconnected':
        return PdfColor.fromHex('#E65100');
      default:
        return PdfColor.fromHex('#FF8F00');
    }
  }

  // ── Share / Save ───────────────────────────────────────────────────────────

  /// Share the PDF via the system share sheet (save to Files, email, etc.).
  static Future<void> sharePdf(Uint8List bytes, String fileName) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }
}
