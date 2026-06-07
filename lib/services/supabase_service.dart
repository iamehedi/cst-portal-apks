import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';
import 'routine_service.dart';

/// Result of [_resizeForUpload] — either resized PNG bytes or the original.
class ResizeResult {
  final Uint8List bytes;
  final bool isPng;

  const ResizeResult._(this.bytes, this.isPng);

  factory ResizeResult.png(Uint8List pngBytes) => ResizeResult._(pngBytes, true);
  factory ResizeResult.original(Uint8List originalBytes) => ResizeResult._(originalBytes, false);
}

class SupabaseService {
  static const supabaseUrl = 'https://cqtbntuyornjwqqzwrdy.supabase.co';
  static const supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxdGJudHV5b3JuandxcXp3cmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNjA2NTAsImV4cCI6MjA5NDczNjY1MH0.X0PaWfIEO0GC9sDbrPchb_-Nb_PHfXIybh3Ql-FQclc';

  static Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // ─── Semester conversion helpers ───────────────────────────
  static const _semesterLabels = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th'];

  /// Convert UI string ('1st', '2nd', ...) to DB int (1, 2, ...).
  static int? semesterToInt(String? label) {
    if (label == null) return null;
    final idx = _semesterLabels.indexOf(label);
    return idx >= 0 ? idx + 1 : int.tryParse(label);
  }

  /// Convert DB int (1, 2, ...) to UI string ('1st', '2nd', ...).
  static String semesterFromInt(int? value) {
    if (value == null || value < 1 || value > 8) return '1st';
    return _semesterLabels[value - 1];
  }

  // ─── Auth ───────────────────────────────────────────────────
  static Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email, password: password);

  static Future<AuthResponse> signUp(String email, String password, {Map<String, dynamic>? data}) =>
      client.auth.signUp(email: email, password: password, data: data);

  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> signOut() async {
    // Clear user-specific profile cache before signing out
    final userId = currentUser?.id;
    if (userId != null) {
      await CacheService.remove(CacheService.profileKey(userId));
    }
    await client.auth.signOut();
  }

  // ─── Profiles ───────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile(String userId) async =>
      await client.from('profiles').select().eq('id', userId).maybeSingle();

  static Future<void> upsertProfile(Map<String, dynamic> data) =>
      client.from('profiles').upsert(data);

  static Future<List<Map<String, dynamic>>> getPendingProfiles() =>
      client.from('profiles').select().eq('status', 'pending');

  /// Auto-create a minimal profile from the current auth user's metadata.
  /// This is the fallback when the DB trigger (on_auth_user_created) was
  /// missing or failed, leaving the user authenticated but without a profile.
  static Future<Map<String, dynamic>?> createProfileFromAuth() async {
    final user = currentUser;
    if (user == null) return null;

    final meta = user.userMetadata ?? {};
    final email = user.email ?? '';
    final name = meta['name']?.toString() ?? email.split('@').firstOrNull ?? 'User';
    final role = meta['role']?.toString() ?? 'student';

    final profile = <String, dynamic>{
      'id': user.id,
      'email': email,
      'name': name,
      'role': role,
      'status': 'pending',
      'semester': meta['semester'] is int
          ? meta['semester']
          : int.tryParse(meta['semester']?.toString() ?? ''),
      'roll': meta['roll']?.toString(),
      'registration': meta['registration']?.toString(),
      'contact': meta['contact']?.toString(),
      'shift': meta['shift']?.toString(),
      'session': meta['session']?.toString(),
      'subject': meta['subject']?.toString(),
      'designation': meta['designation']?.toString(),
    };

    try {
      await client.from('profiles').upsert(profile);
      return profile;
    } catch (e) {
      debugPrint('[SupabaseService] Failed to auto-create profile: $e');
      return null;
    }
  }

  static Future<void> approveProfile(String id) =>
      client.from('profiles').update({'status': 'approved'}).eq('id', id);

  static Future<void> rejectProfile(String id) =>
      client.from('profiles').update({'status': 'rejected'}).eq('id', id);

  /// Completely deletes a user from auth (profile cascades via FK).
  /// Allows re-registration with the same email.
  /// Passes the caller's auth token for server-side admin verification.
  static Future<void> deleteUser(String userId) async {
    final session = client.auth.currentSession;
    final token = session?.accessToken ?? '';
    final response = await client.functions.invoke(
      'delete-user',
      body: {'userId': userId},
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Unknown error';
      throw Exception('Failed to delete user: $error');
    }
  }

  /// Safely delete a user with a fallback: tries the edge function first
  /// (which deletes the auth user). Then deletes the profile row directly
  /// to ensure no orphan rows remain (the FK on profiles(id) does not
  /// cascade-delete by default). If the edge function itself fails
  /// (e.g. on web where edge functions may not be reachable), falls back to
  /// deleting just the profile row so the user at least disappears from the app.
  static Future<void> safeDeleteUser(String userId) async {
    try {
      await deleteUser(userId);
    } catch (e) {
      debugPrint('[SupabaseService] Edge function deleteUser failed, falling back to profile delete: $e');
    }
    // Always delete the profile row too — the FK does not cascade by default,
    // so deleting the auth user alone would leave an orphan profile row blocked
    // from re-registration.
    try {
      await deleteProfile(userId);
    } catch (e) {
      debugPrint('[SupabaseService] Failed to delete profile for $userId: $e');
    }
  }

  static Future<void> deleteProfile(String id) =>
      client.from('profiles').delete().eq('id', id);

  // ─── Students ───────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getStudents({int? semester}) {
    var query = client.from('students').select();
    if (semester != null) {
      return query.eq('semester', semester).order('name');
    }
    return query.order('name');
  }

  /// Real-time stream of students (requires Realtime enabled on 'students' table).
  static Stream<List<Map<String, dynamic>>> getStudentsStream({int? semester}) {
    var query = client.from('students').stream(primaryKey: ['id']);
    if (semester != null) {
      return query.eq('semester', semester).order('name');
    }
    return query.order('name');
  }

  static Future<Map<String, dynamic>?> getStudent(String id) =>
      client.from('students').select().eq('id', id).maybeSingle();

  static Future<void> insertStudent(Map<String, dynamic> data) =>
      client.from('students').insert(data);

  static Future<void> upsertStudent(Map<String, dynamic> data) =>
      client.from('students').upsert(data);

  static Future<void> updateStudent(String id, Map<String, dynamic> data) =>
      client.from('students').update(data).eq('id', id);

  /// Look up a student by their email (not ID) and update their record.
  /// This is needed because [students] has its own auto-generated UUID,
  /// while [profiles] uses the auth user's UUID.  Email is the shared key.
  static Future<void> updateStudentByEmail(String email, Map<String, dynamic> data) async {
    if (email.isEmpty) return;
    final student = await client
        .from('students')
        .select('id')
        .eq('email', email)
        .maybeSingle();
    if (student != null) {
      await client.from('students').update(data).eq('id', student['id']);
    }
  }

  static Future<void> deleteStudent(String id) =>
      client.from('students').delete().eq('id', id);

  // ─── Notices ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getNotices() =>
      client.from('notices').select().order('created_at', ascending: false);

  /// Real-time stream of notices (requires Realtime enabled on 'notices' table).
  static Stream<List<Map<String, dynamic>>> getNoticesStream() =>
      client.from('notices').stream(primaryKey: ['id']).order('created_at', ascending: false);

  static Future<void> insertNotice(Map<String, dynamic> data) =>
      client.from('notices').insert(data);

  static Future<void> updateNotice(String id, Map<String, dynamic> data) =>
      client.from('notices').update(data).eq('id', id);

  static Future<void> deleteNotice(String id) =>
      client.from('notices').delete().eq('id', id);

  // ─── Notes (Study Materials) ────────────────────────────────
  static Future<List<Map<String, dynamic>>> getNotes({int? semester}) {
    var query = client.from('notes').select();
    if (semester != null) {
      return query.eq('semester', semester).order('upload_date', ascending: false);
    }
    return query.order('upload_date', ascending: false);
  }

  /// Real-time stream of notes (requires Realtime enabled on 'notes' table).
  static Stream<List<Map<String, dynamic>>> getNotesStream({int? semester}) {
    var query = client.from('notes').stream(primaryKey: ['id']);
    if (semester != null) {
      return query.eq('semester', semester).order('upload_date', ascending: false);
    }
    return query.order('upload_date', ascending: false);
  }

  static Future<void> insertNote(Map<String, dynamic> data) =>
      client.from('notes').insert(data);

  static Future<void> updateNote(String id, Map<String, dynamic> data) =>
      client.from('notes').update(data).eq('id', id);

  static Future<void> deleteNote(String id) =>
      client.from('notes').delete().eq('id', id);

  // ─── Profile Photo Upload (Supabase Storage) ───────────
  /// Upload a profile photo for the current user to the `student-photos` bucket.
  /// Files are stored at `{authUserId}/profile_{timestamp}.{ext}` so the storage RLS
  /// policy (`name LIKE auth.uid() || '/%'`) grants access to the owner.
  ///
  /// Images are resized to at most 1024×1024 before upload to ensure they
  /// have sufficient resolution for avatar display without wasting bandwidth
  /// and storage on full-resolution camera images.
  ///
  /// Returns the public URL of the uploaded photo.
  static Future<String> uploadProfilePhoto(Uint8List fileBytes, String fileName) async {
    _validateFileSize(fileBytes, fileName);
    final user = currentUser;
    if (user == null) throw Exception('Not signed in');
    final userId = user.id;

    // Resize to optimal size for avatar display (512px is ~3× headroom
    // for a 140px avatar at 3× DPI — far more than enough for sharp display)
    final result = await _resizeForUpload(fileBytes);

    final ext = result.isPng
        ? 'png'
        : (fileName.split('.').lastOrNull ?? 'jpg').toLowerCase();
    await _deleteProfilePhotoFiles(userId);
    final storagePath = '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from('student-photos').uploadBinary(
      storagePath,
      result.bytes,
      fileOptions: FileOptions(
        contentType: result.isPng ? 'image/png' : _mimeType(fileName),
        upsert: false,
      ),
    );
    final publicUrl = client.storage.from('student-photos').getPublicUrl(storagePath);
    return publicUrl;
  }

  /// Delete the current user's profile photo from the `student-photos` bucket.
  static Future<void> deleteProfilePhoto(String userId) async {
    await _deleteProfilePhotoFiles(userId);
  }

  static Future<void> _deleteProfilePhotoFiles(String userId) async {
    final paths = <String>{};
    try {
      final files = await client.storage.from('student-photos').list(path: userId);
      for (final file in files) {
        if (file.name.startsWith('profile.') || file.name.startsWith('profile_')) {
          paths.add('$userId/${file.name}');
        }
      }
    } catch (_) {}

    // Try common extensions — only the one that exists will match
    for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'gif']) {
      try {
        paths.add('$userId/profile.$ext');
      } catch (_) {}
    }

    try {
      await client.storage.from('student-photos').remove(paths.toList());
    } catch (_) {}
  }

  /// Update the `photo_url` in both profiles and students tables.
  static Future<void> updateProfilePhotoUrl(String userId, String photoUrl) async {
    await client.from('profiles').update({'photo_url': photoUrl}).eq('id', userId);
    final profile = await getProfile(userId);
    final email = profile?['email']?.toString();
    if (email != null && email.isNotEmpty) {
      await updateStudentByEmail(email, {'photo_url': photoUrl});
    }
  }

  // ─── Image resize helper ───────────────────────────────────
  /// Resize image bytes to at most [maxDimension] on the longest side.
  /// Uses PNG encoding to preserve quality and support alpha transparency.
  /// If the image is already smaller than [maxDimension], it passes through
  /// at its original size (instantiateImageCodec only downscales — never
  /// upscales). On any decode failure, falls back to original bytes so the
  /// upload can proceed even with unusual or corrupt image data.
  ///
  /// Returns a [ResizeResult] indicating whether the output is PNG or the
  /// original bytes, so callers can set the correct content type.
  static Future<ResizeResult> _resizeForUpload(Uint8List bytes, {int maxDimension = 512}) async {
    try {
      // First decode to get original image dimensions
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;

      // If both dimensions are already within limits, just encode as PNG
      // (no upscaling — that would blur the image, not sharpen it)
      if (w <= maxDimension && h <= maxDimension) {
        final byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData != null) {
          return ResizeResult.png(
            byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          );
        }
        return ResizeResult.original(bytes);
      }

      // Constrain the LONGEST side to maxDimension while maintaining aspect ratio.
      // This is a "fit inside" resize — no stretching, no dimension exceeds maxDimension.
      final scale = maxDimension / (w > h ? w : h);
      final targetWidth = (w * scale).round();
      final targetHeight = (h * scale).round();

      // Re-decode with the correct proportional dimensions
      final resizedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await resizedCodec.getNextFrame();
      final byteData = await resizedFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        return ResizeResult.png(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
      }
    } catch (_) {
      // Fall through to return original bytes
    }
    return ResizeResult.original(bytes);
  }

  // ─── Helpers ──────────────────────────────────────────────
  /// Determine MIME type from the file name using the `mime` package.
  /// Falls back to `application/octet-stream` if unknown.
  static String _mimeType(String fileName) =>
      lookupMimeType(fileName) ?? 'application/octet-stream';

  // ─── File Upload (Supabase Storage) ────────────────────────
  static const int _maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB

  static void _validateFileSize(Uint8List fileBytes, String fileName) {
    if (fileBytes.lengthInBytes > _maxFileSizeBytes) {
      throw Exception('File "$fileName" exceeds 50 MB limit (${(fileBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB).');
    }
  }

  /// Upload a file to the `notes-files` bucket. Accepts bytes directly
  /// (from [file_picker]) for cross-platform compatibility (mobile + web).
  static Future<String> uploadNoteFile(Uint8List fileBytes, String fileName) async {
    _validateFileSize(fileBytes, fileName);
    final user = currentUser;
    if (user == null) throw Exception('Not signed in');
    final userId = user.id;
    final safeName = _sanitizeFileName(fileName);
    final storagePath = '$userId/notes/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await client.storage.from('notes-files').uploadBinary(
      storagePath,
      fileBytes,
      fileOptions: FileOptions(contentType: _mimeType(fileName)),
    );
    final publicUrl = client.storage.from('notes-files').getPublicUrl(storagePath);
    return publicUrl;
  }

  static Future<void> deleteNoteFile(String fileUrl) async {
    const publicPrefix = 'notes-files/';
    final idx = fileUrl.indexOf(publicPrefix);
    if (idx < 0) return;
    final storagePath = fileUrl.substring(idx + publicPrefix.length);
    await client.storage.from('notes-files').remove([storagePath]);
  }

  /// Replace characters invalid for Supabase Storage keys with underscores.
  /// Preserves alphanumerics, hyphens, underscores, dots, and forward slashes.
  static String _sanitizeFileName(String fileName) {
    // Keep only safe chars: a-z, A-Z, 0-9, -, _, ., /
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9\-_\./]'), '_');
  }

  // ─── Notice File Attachment Upload ──────────────────────
  /// Upload a file to the `notice-attachments` bucket. Accepts bytes directly
  /// (from [file_picker]) for cross-platform compatibility (mobile + web).
  static Future<String> uploadNoticeFile(Uint8List fileBytes, String fileName) async {
    _validateFileSize(fileBytes, fileName);
    final user = currentUser;
    if (user == null) throw Exception('Not signed in');
    final userId = user.id;
    final safeName = _sanitizeFileName(fileName);
    final storagePath = '$userId/notices/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await client.storage.from('notice-attachments').uploadBinary(
      storagePath,
      fileBytes,
      fileOptions: FileOptions(contentType: _mimeType(fileName)),
    );
    final publicUrl = client.storage.from('notice-attachments').getPublicUrl(storagePath);
    return publicUrl;
  }

  static Future<void> deleteNoticeFile(String fileUrl) async {
    const publicPrefix = 'notice-attachments/';
    final idx = fileUrl.indexOf(publicPrefix);
    if (idx < 0) return;
    final storagePath = fileUrl.substring(idx + publicPrefix.length);
    await client.storage.from('notice-attachments').remove([storagePath]);
  }

  // ─── Class Routine Slots (see RoutineService) ─────────────────
  static Future<List<Map<String, dynamic>>> getRoutine(int semester) async =>
      (await RoutineService.fetch(semester)).map((slot) => slot.toRow()).toList();

  static Stream<List<Map<String, dynamic>>> getRoutineStream(int semester) =>
      RoutineService.watch(semester).map((slots) => slots.map((s) => s.toRow()).toList());

  static Future<List<Map<String, dynamic>>> getAllRoutines() async {
    final rows = await client
        .from('class_routine_slots')
        .select()
        .order('semester')
        .order('day')
        .order('period_index');
    return rows;
  }

  static Stream<List<Map<String, dynamic>>> getAllRoutinesStream() =>
      client
          .from('class_routine_slots')
          .stream(primaryKey: ['id'])
          .order('semester')
          .order('day')
          .order('period_index');

  static Future<List<int>> getRoutineSemesters() => RoutineService.availableSemesters();

  static Future<void> upsertRoutine(Map<String, dynamic> data) =>
      RoutineService.save(ClassRoutine.fromRow(data));

  static Future<void> upsertRoutineBulk(List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return;
    final semester = RoutineService.parseSemester(data.first['semester']);
    await RoutineService.importBulk(data, semester);
  }

  static Future<void> deleteRoutine(String id) => RoutineService.delete(id);

  // ─── Teachers ───────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTeachers() =>
      client.from('teachers').select().order('teacher_name');

  /// Real-time stream of teachers.
  static Stream<List<Map<String, dynamic>>> getTeachersStream() =>
      client.from('teachers').stream(primaryKey: ['id']).order('teacher_name');

  static Future<void> upsertTeacher(Map<String, dynamic> data) =>
      client.from('teachers').upsert(data);

  static Future<void> deleteTeacher(String id) =>
      client.from('teachers').delete().eq('id', id);

  // ─── Exams ──────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getExams({int? semester}) {
    var query = client.from('exams').select();
    if (semester != null) {
      return query.eq('semester', semester).order('exam_date');
    }
    return query.order('exam_date');
  }

  /// Real-time stream of exams (requires Realtime enabled on 'exams' table).
  static Stream<List<Map<String, dynamic>>> getExamsStream({int? semester}) {
    var query = client.from('exams').stream(primaryKey: ['id']);
    if (semester != null) {
      return query.eq('semester', semester).order('exam_date');
    }
    return query.order('exam_date');
  }

  static Future<void> upsertExam(Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await client.from('exams').update(data).eq('id', id);
    } else {
      data.remove('id');
      await client.from('exams').insert(data);
    }
  }

  static Future<void> deleteExam(String id) =>
      client.from('exams').delete().eq('id', id);

  // ─── College Off Days ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getOffDays() =>
      client.from('college_off_days').select().order('start_date');

  /// Real-time stream of off days.
  static Stream<List<Map<String, dynamic>>> getOffDaysStream() =>
      client.from('college_off_days').stream(primaryKey: ['id']).order('start_date');

  /// Fetch only current & future off days (today onwards).
  static Future<List<Map<String, dynamic>>> getFutureOffDays() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final all = await getOffDays();
    return all.where((d) {
      final end = d['end_date']?.toString() ?? '';
      return end.compareTo(today) >= 0;
    }).toList();
  }

  /// Check if today (or a given date) falls within any off period.
  static Future<bool> isDateOff(DateTime date) async {
    final dateStr = date.toIso8601String().substring(0, 10);
    final offDays = await getOffDays();
    for (final day in offDays) {
      final start = day['start_date']?.toString() ?? '';
      final end = day['end_date']?.toString() ?? '';
      if (start.compareTo(dateStr) <= 0 && dateStr.compareTo(end) <= 0) return true;
    }
    return false;
  }

  /// Check if today is an off day (fast, no date param).
  static Future<bool> isTodayOff() => isDateOff(DateTime.now());

  static Future<void> insertOffDay(Map<String, dynamic> data) =>
      client.from('college_off_days').insert(data);

  static Future<void> deleteOffDay(String id) =>
      client.from('college_off_days').delete().eq('id', id);

  // ─── Events (General College Events) ────────────────────
  /// Fetch all upcoming events (today onwards).
  static Future<List<Map<String, dynamic>>> getEvents() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return client
        .from('events')
        .select()
        .gte('event_date', today)
        .order('event_date');
  }

  /// Fetch all events (past & future).
  static Future<List<Map<String, dynamic>>> getAllEvents() =>
      client.from('events').select().order('event_date');

  /// Real-time stream of all events.
  static Stream<List<Map<String, dynamic>>> getEventsStream() =>
      client.from('events').stream(primaryKey: ['id']).order('event_date');

  static Future<void> insertEvent(Map<String, dynamic> data) =>
      client.from('events').insert(data);

  static Future<void> updateEvent(String id, Map<String, dynamic> data) =>
      client.from('events').update(data).eq('id', id);

  static Future<void> deleteEvent(String id) =>
      client.from('events').delete().eq('id', id);

  // ─── Device Tokens (for push notifications) ─────────────────
  static Future<List<Map<String, dynamic>>> getAllDeviceTokens() =>
      client.from('device_tokens').select('device_token');

  static Future<Map<String, dynamic>?> getDeviceToken(String userId) async =>
      await client.from('device_tokens').select().eq('user_id', userId).maybeSingle();

  static Future<void> upsertDeviceToken(Map<String, dynamic> data) =>
      client.from('device_tokens').upsert(data, onConflict: 'user_id');

  static Future<void> deleteDeviceToken(String userId) =>
      client.from('device_tokens').delete().eq('user_id', userId);

  // ─── Real-time stream of pending profile approvals ─────────────────
  static Stream<List<Map<String, dynamic>>> getPendingProfilesStream() =>
      client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('status', 'pending')
          .order('created_at');

  /// Real-time stream of approved student profiles.
  /// Used in [StudentsScreen] to show registered users alongside the
  /// legacy [students] table.
  static Stream<List<Map<String, dynamic>>> getApprovedStudentProfilesStream() =>
      client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('role', 'student')
          .order('name');
}
