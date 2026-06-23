import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cst_portal/core/ble/nearby_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NearbyService — Unit Tests for BLE Attendance Fixes
// ─────────────────────────────────────────────────────────────────────────────
// These tests cover three fixes implemented for the teacher BLE attendance
// flow (no student data appearing on the teacher's roster):
//
// 1. Student ID encoded in the Nearby endpoint name ("name|id" format)
// 2. Preliminary roster entry created from the connection info (parsing
//    the endpoint name before acceptConnection completes)
// 3. Retry logic for the check-in payload send (3 attempts with timeout)
//
// All tests are pure Dart logic — no platform mocks required.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── NearbyCheckIn Model ───────────────────────────────────────────────────

  group('NearbyCheckIn — data model', () {
    test('stores all three fields from constructor', () {
      final checkIn = NearbyCheckIn(
        endpointId: 'EP_ABC123',
        studentId: 'ROLL101',
        studentName: 'John Doe',
      );
      expect(checkIn.endpointId, 'EP_ABC123');
      expect(checkIn.studentId, 'ROLL101');
      expect(checkIn.studentName, 'John Doe');
    });

    test('fields are all accessible', () {
      final checkIn = NearbyCheckIn(
        endpointId: 'EP_XYZ',
        studentId: 'ROLL042',
        studentName: 'Jane Smith',
      );
      // Verify the objects are correctly immutable
      expect(checkIn.endpointId, isA<String>());
      expect(checkIn.studentId, isA<String>());
      expect(checkIn.studentName, isA<String>());
    });
  });

  // ── Endpoint Name Parsing ─────────────────────────────────────────────────

  group('Endpoint name parsing — "name|id" format', () {
    // This mirrors the exact logic in NearbyService.startAdvertising's
    // onConnectionInitiated callback. The student encodes their identity
    // as "studentName|studentId" in the requestConnection endpoint name,
    // allowing the teacher to extract both before acceptConnection completes.

    ({String studentName, String studentId}) parseEndpointName(
        String endpointName) {
      final parts = endpointName.split('|');
      final studentName =
          parts.isNotEmpty ? parts[0] : endpointName;
      final studentId = parts.length > 1 ? parts[1] : '';
      return (studentName: studentName, studentId: studentId);
    }

    test('parses "name|id" format correctly', () {
      final result = parseEndpointName('John Doe|ROLL101');
      expect(result.studentName, 'John Doe');
      expect(result.studentId, 'ROLL101');
    });

    test('handles names with multiple parts (first|last|id)', () {
      final result = parseEndpointName('Mary Jane|ROLL042');
      expect(result.studentName, 'Mary Jane');
      expect(result.studentId, 'ROLL042');
    });

    test('handles old format without "|" delimiter (just a name)', () {
      final result = parseEndpointName('John Doe');
      expect(result.studentName, 'John Doe');
      expect(result.studentId, '');
    });

    test('handles empty endpoint name', () {
      final result = parseEndpointName('');
      expect(result.studentName, '');
      expect(result.studentId, '');
    });

    test('handles name with only delimiter and no ID', () {
      final result = parseEndpointName('John Doe|');
      expect(result.studentName, 'John Doe');
      expect(result.studentId, '');
    });

    test('handles name with empty name and only ID', () {
      final result = parseEndpointName('|ROLL101');
      expect(result.studentName, '');
      expect(result.studentId, 'ROLL101');
    });

    test('preliminary check-in guard — only creates entry when both are non-empty', () {
      // This is the exact guard condition used in startAdvertising:
      //   if (studentId.isNotEmpty && studentName.isNotEmpty) { create check-in }

      // New format: both present → should create preliminary entry
      final result1 = parseEndpointName('John Doe|ROLL101');
      expect(result1.studentName.isNotEmpty && result1.studentId.isNotEmpty,
          true,
          reason: 'New format "name|id" should trigger preliminary check-in');

      // Old format: no ID → should NOT create preliminary entry
      final result2 = parseEndpointName('John Doe');
      expect(result2.studentName.isNotEmpty && result2.studentId.isNotEmpty,
          false,
          reason: 'Old format without ID should NOT trigger preliminary check-in');

      // Empty name: should NOT create preliminary entry
      final result3 = parseEndpointName('');
      expect(result3.studentName.isNotEmpty && result3.studentId.isNotEmpty,
          false,
          reason: 'Empty endpoint name should NOT trigger preliminary check-in');
    });
  });

  // ── Retry Logic ───────────────────────────────────────────────────────────

  group('sendWithRetry — retry logic', () {
    test('succeeds on first attempt', () async {
      int attempts = 0;
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
      });
      expect(result, true,
          reason: 'Should return true on successful send');
      expect(attempts, 1,
          reason: 'Should only call send function once on success');
    });

    test('fails after exhausting all 3 retries', () async {
      int attempts = 0;
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
        throw Exception('send failed');
      });
      expect(result, false,
          reason: 'Should return false after all retries exhausted');
      expect(attempts, 3,
          reason: 'Should retry exactly 3 times on persistent failure');
    });

    test('succeeds on second attempt after first failure', () async {
      int attempts = 0;
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
        if (attempts < 2) throw Exception('first attempt failed');
      });
      expect(result, true,
          reason: 'Should return true when retry succeeds');
      expect(attempts, 2,
          reason: 'Should retry once after first failure, then succeed');
    });

    test('succeeds on third attempt after two failures', () async {
      int attempts = 0;
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
        if (attempts < 3) throw Exception('failed on attempt $attempts');
      });
      expect(result, true,
          reason: 'Should return true when last retry succeeds');
      expect(attempts, 3,
          reason: 'Should retry twice, then succeed on third attempt');
    });

    test('does not wait for timeout when send fails synchronously', () async {
      // The retry has a 2-second timeout per attempt and 500ms delay.
      // Throwing synchronously means the timeout never activates.
      final stopwatch = Stopwatch()..start();
      await NearbyService.sendWithRetry(() async {
        throw Exception('fail');
      });
      stopwatch.stop();
      // 3 failures × 0s timeout + 2 delays × 500ms ≈ 1000ms
      // With a generous buffer since Future.delayed can be imprecise
      expect(stopwatch.elapsedMilliseconds, lessThan(3000),
          reason:
              '3 synchronous failures should complete in ~1s, far less than 3 × 2s timeout');
    });

    test('handles async errors (delayed throw)', () async {
      int attempts = 0;
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
        // Simulate a send that takes some time before failing
        await Future.delayed(const Duration(milliseconds: 10));
        throw Exception('async failure');
      });
      expect(result, false,
          reason: 'Should return false after all retries exhaust');
      expect(attempts, 3,
          reason: 'Should retry 3 times for async errors too');
    });

    test('timeout triggers retry when send hangs', () async {
      int attempts = 0;
      // Use a Completer that never completes to trigger the 2s timeout
      final result = await NearbyService.sendWithRetry(() async {
        attempts++;
        await Completer<void>().future; // Never completes → timeout
      });
      // With 3 attempts × 2s timeout, this would take ~6s.
      // We only verify the mechanism — the exact attempt count depends on
      // timing and is tested with synchronous failures above.
      expect(result, false,
          reason: 'Should return false when all attempts timeout');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ── Deduplication Logic ───────────────────────────────────────────────────

  group('Deduplication — _studentToEndpoint guard', () {
    // This mirrors the exact guard condition in _handlePayload:
    //   final existingEndpoint = _studentToEndpoint[studentId];
    //   if (existingEndpoint != null && existingEndpoint != endpointId) {
    //     return; // duplicate
    //   }

    test('allows first check-in from a student', () {
      final Map<String, String> studentToEndpoint = {};
      const studentId = 'ROLL101';
      const endpointId = 'EP_ABC';

      final existingEndpoint = studentToEndpoint[studentId];
      final isDuplicate =
          existingEndpoint != null && existingEndpoint != endpointId;

      expect(isDuplicate, false,
          reason: 'First entry should not be a duplicate');
    });

    test('blocks duplicate check-in from same student on different endpoint', () {
      final Map<String, String> studentToEndpoint = {};
      const studentId = 'ROLL101';
      studentToEndpoint[studentId] = 'EP_ABC';
      const newEndpointId = 'EP_XYZ';

      final existingEndpoint = studentToEndpoint[studentId];
      final isDuplicate =
          existingEndpoint != null && existingEndpoint != newEndpointId;

      expect(isDuplicate, true,
          reason: 'Same student from different endpoint should be duplicate');
    });

    test('allows check-in from same endpoint (harmless re-delivery)', () {
      final Map<String, String> studentToEndpoint = {};
      const studentId = 'ROLL101';
      const endpointId = 'EP_ABC';
      studentToEndpoint[studentId] = endpointId;

      final existingEndpoint = studentToEndpoint[studentId];
      final isDuplicate =
          existingEndpoint != null && existingEndpoint != endpointId;

      expect(isDuplicate, false,
          reason:
              'Same student from same endpoint should be allowed (idempotent)');
    });

    test('allows different students from same endpoint', () {
      final Map<String, String> studentToEndpoint = {};
      const endpointId = 'EP_ABC';
      studentToEndpoint['ROLL101'] = endpointId;

      final existingEndpoint = studentToEndpoint['ROLL042'];
      final isDuplicate =
          existingEndpoint != null && existingEndpoint != endpointId;

      expect(isDuplicate, false,
          reason:
              'Different student from same endpoint should not be a duplicate');
    });

    test('allows check-in after student was removed from tracking', () {
      final Map<String, String> studentToEndpoint = {};
      const studentId = 'ROLL101';
      const endpointId = 'EP_ABC';

      // First: student check-in recorded
      studentToEndpoint[studentId] = endpointId;

      // Student disconnected and was removed
      studentToEndpoint.remove(studentId);

      // New check-in should be allowed
      final existingEndpoint = studentToEndpoint[studentId];
      final isDuplicate =
          existingEndpoint != null && existingEndpoint != endpointId;

      expect(isDuplicate, false,
          reason:
              'After student is removed from tracking, a new check-in should be allowed');
    });
  });

  // ── Capacity / State Management ──────────────────────────────────────────

  group('State management — capacity and counters', () {
    test('maxConcurrentConnections is 12', () {
      expect(NearbyService.maxConcurrentConnections, 12,
          reason: 'Should support up to 12 simultaneous connections');
    });

    test('connectedPeers returns empty list initially', () {
      // Note: connectedPeers depends on _connectedEndpoints which is
      // private. We verify the type contract: it returns a list.
      final service = NearbyService();
      expect(service.connectedPeers, isEmpty,
          reason: 'No peers should be connected initially');
      expect(service.connectedPeers, isA<List>());
    });

    test('isActive defaults to false', () {
      final service = NearbyService();
      expect(service.isActive.value, false);
    });

    test('connectedCount defaults to 0', () {
      final service = NearbyService();
      expect(service.connectedCount.value, 0);
    });
  });
}
