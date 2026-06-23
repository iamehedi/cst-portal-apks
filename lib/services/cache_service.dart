import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';

class CacheService {
  static late SharedPreferences _prefs;

  /// Maximum age for cached data before it's considered stale when online.
  /// Extended to 24 hours — data survives a full school day.
  /// When offline, stale check is bypassed entirely.
  static const Duration maxCacheAge = Duration(hours: 24);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Check if a cache entry is stale.
  /// When offline, always returns false (data is never stale).
  /// When online, returns true if data is older than [maxCacheAge] or missing.
  static bool isStale(String key) {
    if (!ConnectivityService().isOnline.value) return false;
    final ts = lastUpdated(key);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > maxCacheAge;
  }



  // ─── List cache (notices, notes, students, etc.) ─────────────

  static Future<void> saveList(String key, List<Map<String, dynamic>> data) async {
    final json = jsonEncode(data);
    await _prefs.setString(key, json);
    await _prefs.setString('${key}_ts', DateTime.now().toIso8601String());
  }

  static List<Map<String, dynamic>>? loadList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return null;
  }

  // ─── Single map cache (profile) ─────────────────────────────

  static Future<void> saveMap(String key, Map<String, dynamic> data) async {
    final json = jsonEncode(data);
    await _prefs.setString(key, json);
    await _prefs.setString('${key}_ts', DateTime.now().toIso8601String());
  }

  static Map<String, dynamic>? loadMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  /// Invalidate all cached data by removing all timestamp keys.
  /// Forces the next [isStale] check to return `true` for every cache entry,
  /// so screens will re-fetch fresh data from Supabase.
  static Future<void> invalidateAllCaches() async {
    final keys = _prefs.getKeys().where((k) => k.endsWith('_ts')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  // ─── Utilities ───────────────────────────────────────────────

  static Future<void> remove(String key) async {
    await _prefs.remove(key);
    await _prefs.remove('${key}_ts');
  }

  static DateTime? lastUpdated(String key) {
    final raw = _prefs.getString('${key}_ts');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Get the raw string value stored under [key] (for unread timestamps).
  static String? getRaw(String key) => _prefs.getString(key);

  // ─── Cache key helpers (scoped by user where needed) ────────

  static String profileKey(String userId) => 'cache_profile_$userId';

  static const noticesKey = 'cache_notices';

  static String notesKey([int? semester]) =>
      semester != null ? 'cache_notes_sem$semester' : 'cache_notes_all';

  static const examsKey = 'cache_exams';
  static String examsKeySemester(int semester) => 'cache_exams_sem$semester';

  static const eventsKey = 'cache_events';
  static const offDaysKey = 'cache_off_days';
  static const studentsKey = 'cache_students';
  static const profilesKey = 'cache_profiles';
  static const teachersKey = 'cache_teachers';
  static String routineKey(int semester) => 'cache_routine_sem$semester';


  // ─── Unread notification tracking ─────────────────────────

  static const String unreadNoticesKey = 'unread_notices_ts';
  static const String unreadNotesKey = 'unread_notes_ts';
  static const String unreadEventsKey = 'unread_events_ts';

  /// Mark a content type as viewed (stores current timestamp).
  static Future<void> markViewed(String key) async {
    await _prefs.setString(key, DateTime.now().toIso8601String());
  }

  /// Returns true if the latest item in [items] is newer than the last
  /// viewed timestamp stored under [key].
  ///
  /// Checks [createdAtField] (default `'created_at'`) on each item.
  static bool hasUnread(String key, List<Map<String, dynamic>> items,
      {String createdAtField = 'created_at'}) {
    if (items.isEmpty) return false;
    // Find the most recent timestamp among items
    DateTime? latest;
    for (final item in items) {
      final ts = DateTime.tryParse(item[createdAtField]?.toString() ?? '');
      if (ts != null && (latest == null || ts.isAfter(latest))) {
        latest = ts;
      }
    }
    if (latest == null) return false;
    final lastViewed = _prefs.getString(key);
    if (lastViewed == null) return true;
    final viewed = DateTime.tryParse(lastViewed);
    if (viewed == null) return true;
    return latest.isAfter(viewed);
  }
}
