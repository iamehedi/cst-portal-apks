import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/connectivity_service.dart';
import '../db/local_database.dart';

class SyncEngine {
  static const int _batchSize = 50;
  static const int _maxRetries = 5;

  static SupabaseClient get _client => SupabaseService.client;

  /// Syncs all pending/failed local attendance records to Supabase.
  /// Returns the number of records successfully synced.
  static Future<int> syncPendingRecords() async {
    if (!ConnectivityService().isOnline.value) return 0;

    final records = await LocalDatabase.getPendingRecords();
    if (records.isEmpty) return 0;

    int syncedCount = 0;
    int failedCount = 0;

    for (var i = 0; i < records.length; i += _batchSize) {
      final batch = records.skip(i).take(_batchSize).toList();
      for (final record in batch) {
        try {
          final success = await _syncSingleRecord(record);
          if (success) {
            syncedCount++;
          } else {
            failedCount++;
          }
        } catch (e) {
          failedCount++;
          await LocalDatabase.markRecordFailed(record['id'] as String);
          debugPrint('[SyncEngine] Failed to sync record ${record['id']}: $e');
        }
      }
    }

    if (syncedCount > 0) {
      await LocalDatabase.deleteOldSyncedRecords();
    }

    debugPrint('[SyncEngine] Synced $syncedCount, failed $failedCount records');
    return syncedCount;
  }

  static Future<bool> _syncSingleRecord(Map<String, dynamic> record) async {
    final id = record['id'] as String;
    final retryCount = (record['retry_count'] as int?) ?? 0;

    if (retryCount >= _maxRetries) {
      return false;
    }

    final method = record['method']?.toString() ?? 'offline_qr';
    final token = record['token']?.toString();

    final attendanceData = {
      'id': id,
      'student_id': record['student_id'],
      'student_name': record['student_name'],
      'class': record['class'],
      'subject': record['subject'],
      'status': record['status'] ?? 'present',
      'marked_at': record['scanned_at'],
      'method': method,
      'marked_by': SupabaseService.currentUser?.id,
      'device_id': record['device_id'],
    };

    if (record['session_id'] != null && record['session_id'].toString().isNotEmpty) {
      attendanceData['session_id'] = record['session_id'];
    }

    try {
      if (token != null && token.isNotEmpty && record['session_id'] != null) {
        final result = await _client.rpc('validate_and_mark_attendance', params: {
          'p_session_id': record['session_id'],
          'p_token': token,
          'p_student_id': record['student_id'],
          'p_student_name': record['student_name'] ?? '',
          'p_method': method,
          'p_user_id': SupabaseService.currentUser?.id,
        });

        if (result is Map && result['success'] == true) {
          await LocalDatabase.markRecordSynced(id);
          return true;
        } else {
          await LocalDatabase.markRecordFailed(id);
          return false;
        }
      } else {
        await _client.from('attendance_records').upsert(attendanceData);
        await LocalDatabase.markRecordSynced(id);
        return true;
      }
    } catch (e) {
      await LocalDatabase.markRecordFailed(id);
      rethrow;
    }
  }

  /// Force retry all failed records (manual sync trigger).
  static Future<int> retryFailedRecords() async {
    return syncPendingRecords();
  }
}
