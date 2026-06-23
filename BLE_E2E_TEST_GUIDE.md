# BLE Attendance — Real Android Device E2E Test Guide

This guide covers how to manually test the BLE Smart Attendance system on **two real Android phones** (one acting as Teacher, one as Student). The unit tests (`test/ble_session_e2e_test.dart`, `test/attendance_report_ble_merge_test.dart`) verify the database layer, but BLE hardware and the Nearby Connections plugin can only be tested on actual devices.

---

## Prerequisites

### Hardware
- **Two Android phones** (both running Android 8+; Android 12+ recommended for the best BLE permission handling)
- Bluetooth must be working on both devices

### Software
- Build and install the app on both phones: `flutter run` (or `flutter build apk --debug` then `adb install`)
- Both phones logged in with appropriate roles:
  - **Teacher phone**: logged in as a user with `role = 'teacher'` or `role = 'admin'`
  - **Student phone**: logged in as a user with `role = 'student'`

### Permissions
- Grant **Bluetooth** and **Location** permissions when prompted
- On Android 12+: grant `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`
- On Android 11 and below: grant `ACCESS_FINE_LOCATION` (required by OS for BLE scanning)
- The app does **NOT** use WiFi — see Scenario 4 to verify this

### Running Two Debug Instances Simultaneously

**Yes — you can debug both phones at the same time.** Use two separate terminal windows:

```bash
# Terminal 1 — Teacher phone
flutter devices                               # Copy device IDs
flutter run -d <teacher_device_id> --debug    # Run on teacher phone
```

```bash
# Terminal 2 — Student phone
flutter run -d <student_device_id> --debug    # Run on student phone
```

**Alternative: Build APK (no wires needed):**
```bash
flutter build apk --debug
# Install on both phones via USB or side-load
```

**Watch logs per device:**
```bash
# Teacher logs (in one terminal)
flutter logs -d <teacher_id> | findstr "[BleTeacher] [Nearby] [BleSession]"

# Student logs (in another terminal)
flutter logs -d <student_id> | findstr "[BleStudent] [Nearby] [BleAttendance]"
```

> **Tip:** Hot reload works independently on each device. Save changes and both will update automatically.

---

## Scenario 1: Normal BLE Attendance Flow

**Objective:** Verify the basic teacher-student BLE attendance loop works end-to-end.

### Steps

| Step | Teacher Phone | Student Phone | Expected |
|------|---------------|---------------|----------|
| 1 | Open Smart Attendance → select subject → tap **Start Attendance** | — | Teacher sees "Session Active" banner, counters: Connected 0, Detected 0, Pending 0 |
| 2 | — | Open Smart Attendance → tap **Start Scanning** | Student sees "Searching for class..." with spinner |
| 3 | — | (Wait up to 30s) | Student sees "Class Found — {subject}", then "Connecting..." |
| 4 | — | (Wait) | Student sees "Check-in submitted!" or "Waiting for Approval" with hourglass icon |
| 5 | Teacher sees student appear in Live Roster as **Pending** with Approve/Reject buttons | — | Teacher counters: Connected ≥1, Detected ≥1, Pending ≥1 |
| 6 | Tap **Approve** on the student | — | Student disappears from Pending, appears with green **Present** badge |
| 7 | — | Student sees dialog: **Present ✅** with subject name | Dialog shows "Your attendance has been recorded locally." |

### Verification Checklist
- [ ] Teacher counters show correct numbers throughout
- [ ] Student goes through the full state machine: **Found → Connecting → Pending → Present**
- [ ] No state is skipped
- [ ] Student sees "Waiting for Approval" (not "Present") before teacher approves
- [ ] Dialog appears on student phone after approval

---

## Scenario 2: Two Consecutive Sessions — Ghost Attendance Prevention

**Objective:** Verify that ending one session and starting another does NOT carry over student data. This is the **critical Bug 1 & 4 test**.

### Steps

| Step | Teacher Phone | Student Phone | Expected |
|------|---------------|---------------|----------|
| 1 | Start Session 1 (Mathematics) | — | Session active, counters all 0 |
| 2 | — | Scan and check in | Student becomes Pending |
| 3 | Approve the student | — | Student Present in Session 1 |
| 4 | Tap **Stop** → Confirm | — | "Session closed" snackbar |
| 5 | Student returns to idle screen | Teacher returns to start form | Both show the start screen |
| 6 | **Start Session 2 (Python)** | — | **Critical:** Counters must all be 0! Connected=0, Detected=0, Pending=0 |
| 7 | — | Tap **Start Scanning** again | Student scans fresh — should find the NEW Python beacon |
| 8 | — | Check in | Student becomes Pending |
| 9 | Approve the student | — | Student Present in Session 2 |

### What SHOULD NOT Happen (If Bug 1 is Fixed)
- ❌ Student showing as "Present" immediately in Session 2 without checking in
- ❌ Counters showing anything other than 0 when Session 2 starts
- ❌ Student being blocked from checking in to Session 2 because "already in roster"
- ❌ Any student data from Session 1 visible in Session 2's Live Roster

### What to Check
- [ ] When Session 2 starts, ALL counters are **exactly 0**
- [ ] The roster is **completely empty** when Session 2 starts
- [ ] Student must go through the full flow again: Found → Connecting → Pending → Present
- [ ] Session 1 data (approved students) does NOT appear in Session 2

---

## Scenario 3: Student Rejection

**Objective:** Verify the teacher can reject a student and the student sees the correct status.

### Steps

| Step | Teacher Phone | Student Phone | Expected |
|------|---------------|---------------|----------|
| 1 | Start a session | — | Session active |
| 2 | — | Check in | Student becomes Pending |
| 3 | Tap **Reject** on the student | — | Student shows red **Rejected** badge |
| 4 | — | Student sees dialog: **Rejected ❌** | — |

### Verification Checklist
- [ ] Rejected student shows with red badge on teacher's Live Roster
- [ ] Student phone shows "Rejected ❌" dialog
- [ ] Student can scan again for a new/different session (not blocked)

---

## Scenario 4: No WiFi Involvement (Bug 2 Verification)

**Objective:** Verify that the BLE attendance flow works 100% offline with no WiFi dependency.

### Steps

| Step | Teacher Phone | Student Phone | Expected |
|------|---------------|---------------|----------|
| 1 | Enable **Airplane Mode** on both phones | — | No WiFi, no mobile data |
| 2 | Turn on **Bluetooth** only | — | Bluetooth on, everything else off |
| 3 | Start a session | — | Session starts successfully (BLE only) |
| 4 | — | Scan and check in | Student connects and submits check-in |
| 5 | Approve the student | — | Approval works over BLE/Nearby |

### Verification Checklist
- [ ] BLE attendance works with **no SIM card, no WiFi, no internet**
- [ ] No "No internet connection" errors during attendance flow
- [ ] WiFi does NOT turn on automatically when BLE scanning starts
- [ ] `ACCESS_FINE_LOCATION` permission prompt does NOT trigger WiFi scans
- [ ] Check that WiFi icon does NOT appear in status bar during the session

### How to Verify BLE-Only (No WiFi)
1. On Android 12+ devices, go to **Settings → Connections → WiFi** and verify WiFi stays OFF
2. On Android 11-, the `ACCESS_FINE_LOCATION` permission may prompt a one-time WiFi scan. This is an OS behavior, not the app. The app itself never calls any WiFi API.
3. The `NEARBY_WIFI_DEVICES` permission has been **removed** from the manifest.

---

## Scenario 5: Bluetooth Off / Retry

**Objective:** Verify graceful handling when Bluetooth is turned off mid-session.

### Steps

| Step | Teacher Phone | Student Phone | Expected |
|------|---------------|---------------|----------|
| 1 | Start a session | — | Session active |
| 2 | Turn off Bluetooth | — | Teacher sees "Bluetooth Off" warning card with Retry button |
| 3 | Turn on Bluetooth and tap **Retry** | — | Session resumes, BLE advertising restarts |
| 4 | — | Scan and check in | Normal flow resumes |

### Verification Checklist
- [ ] Teacher sees clear "Bluetooth Off" warning
- [ ] Retry button works and restores the session
- [ ] Roster data is preserved through the Bluetooth restart
- [ ] No crashes when Bluetooth toggles

---

## Scenario 6: State Machine Verification (Bug 3)

**Objective:** Verify that the state machine transitions correctly — no state may be skipped.

### Flow Diagram
```
NOT_IN_RANGE
    ↓ (BLE advertisement received)
DETECTED (found) ← student appears on teacher's roster, status pending
    ↓ (student connects via Nearby)
CONNECTED (connecting) ← teacher connected counter increments
    ↓ (student submits check-in)
PENDING (pending) ← teacher sees approval request
    ↓ (teacher presses Approve)
PRESENT (approved) ← final confirmed attendance, green badge
    
    OR
    ↓ (teacher presses Reject)
ABSENT (rejected) ← marked absent, red badge
```

### Verification Checklist
- [ ] Each state is visually distinct on the student's screen
  - `found`: "Class Found — {subject}" with check icon
  - `connecting`: "Connecting..." with spinner
  - `pending`: "Waiting for Approval" with hourglass icon (this is new after Bug 3 fix)
  - `approved`: "Present ✅" dialog
  - `rejected`: "Rejected ❌" dialog
- [ ] Student NEVER sees "Present ✅" without first seeing "Waiting for Approval"
- [ ] Teacher NEVER sees a student jump from "not in roster" to "Present" without going through "Pending"

---

## Scenario 7: Multiple Students

**Objective:** Verify the system handles multiple students connecting simultaneously.

### Steps

| Step | Teacher Phone | Student Phones | Expected |
|------|---------------|----------------|----------|
| 1 | Start a session | — | Session active |
| 2 | — | 2+ student phones each scan and check in | Each appears as Pending |
| 3 | Approve one student | — | That student becomes Present; others remain Pending |
| 4 | Tap **Approve All (N)** | — | All pending students approved in batch |
| 5 | — | Each sees "Present ✅" | All approved |

### Verification Checklist
- [ ] Each student appears independently in the roster
- [ ] Approve/Reject on one student doesn't affect others
- [ ] "Approve All" processes all pending students
- [ ] Teacher counters reflect: Connected, Detected (roster length), Pending separately
- [ ] No duplicate entries for the same student
- [ ] Max concurrent connections (12) are properly managed

---

## Scenario 8: Attendance Report Verification (Admin Side)

**Objective:** Verify that the attendance report correctly reflects BLE session data and that sessions are isolated.

### Steps

| Step | Action | Expected |
|------|--------|----------|
| 1 | After completing Scenarios 1-3, open **Attendance Reports** from the teacher or admin dashboard | Reports load with data |
| 2 | Find the date of the test sessions | Both Mathematics and Python sessions appear |
| 3 | Tap into the Mathematics session | Shows student(s) who checked in |
| 4 | Go back and tap into the Python session | Shows ONLY students who checked in to Python |
| 5 | Verify: Student A appears in BOTH sessions (if they attended both) | Correct — multi-subject attendance is allowed |
| 6 | Verify: Student B (if rejected) appears correctly | Shows rejected/absent status |

### Verification Checklist
- [ ] Mathematics session shows **only** students who checked into Math
- [ ] Python session shows **only** students who checked into Python
- [ ] Same student in both sessions = shown in both (not blocked)
- [ ] No ghost records from cross-session contamination
- [ ] PDF export works correctly

---

## Debugging Tips

### Enable Debug Logging
Run on both devices with:
```bash
flutter run --debug
```

Watch the logs:
```bash
flutter logs
```

Filter for BLE/Nearby messages:
```bash
flutter logs | findstr "[BleTeacher]"
flutter logs | findstr "[BleStudent]"
flutter logs | findstr "[Nearby]"
flutter logs | findstr "[BleSession]"
flutter logs | findstr "[BleAttendance]"
```

### Key Log Messages to Check
| Log Message | Meaning |
|-------------|---------|
| `[BleTeacher] Advertising session: ATT_...` | Teacher started BLE advertising |
| `[BleStudent] Beacon found: ATT_...` | Student detected teacher's beacon |
| `[Nearby] Connected to teacher` | Nearby connection established |
| `[Nearby] Sent check-in for ...` | Student sent check-in payload |
| `[Nearby] Sent approval: present to ...` | Teacher sent approval |

### Common Issues
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Student can't find teacher's beacon | Bluetooth off / Distance too far | Ensure BT on, phones within 5m |
| Teacher shows "Failed to start BLE beacon" | BLE permissions not granted | Check app permissions |
| Student stuck on "Connecting..." | Nearby Connections blocked | Check both phones have Google Play Services |
| Session starts with non-zero counters | Previous session state not cleared (Bug 1) | This should be fixed. If seen, restart the app. |
| WiFi turns on during BLE scan | OS-level behavior (Android < 12) (Bug 2) | Expected — not app-related. The `NEARBY_WIFI_DEVICES` permission was removed. |

---

## Bug-Specific Verification Summary

| Bug | What to Test | Success Criteria |
|-----|-------------|-----------------|
| **Bug 1 & 4:** Ghost Attendance / No Session Isolation | Scenario 2 (two consecutive sessions) | Session 2 starts with counters=0, roster=empty. Student must re-check-in. |
| **Bug 2:** WiFi in BLE App | Scenario 4 (Airplane Mode + BT only) | Attendance works fully offline. WiFi stays off. No WiFi permissions declared. |
| **Bug 3:** State Machine Skip | Scenario 1 & 6 (full flow) | Student must go through all states: Found → Connecting → Pending → Present. No skipping. |

---

## Related Unit Tests

These unit tests run without hardware and verify the database layer:

| Test File | What It Tests |
|-----------|---------------|
| `test/ble_session_e2e_test.dart` | Full two-session lifecycle with in-memory SQLite |
| `test/ble_attendance_subject_isolation_test.dart` | Session encoding, provider state clearing, duplicate checks |
| `test/attendance_report_ble_merge_test.dart` | Report merging with session isolation |
| `test/nearby_service_test.dart` | Nearby retry logic, endpoint parsing, deduplication |

Run all unit tests:
```bash
flutter test
```
