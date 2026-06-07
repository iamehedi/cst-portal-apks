# CST Portal — Real-Time Updates & FCM Push Notifications
## Implementation Guide

---

## Overview of Changes

| Area | Status Before | Status After |
|---|---|---|
| Notices screen | ✅ `StreamBuilder` already | No change needed |
| Notes screen | ✅ `StreamSubscription` already | No change needed |
| Students screen | ✅ `StreamSubscription` already | No change needed |
| Teachers screen | ✅ `StreamSubscription` already | No change needed |
| Routine screen | ✅ `StreamSubscription` already | No change needed |
| Exam routine screen | ✅ `StreamSubscription` already | No change needed |
| **Admin pending count** | ❌ `Future.then()` — no live update | ✅ `StreamSubscription` via `getPendingProfilesStream()` |
| **FCM notification service** | ✅ Mostly complete | ✅ Refactored with clearer comments, channel objects, `printToken()` helper |
| **main.dart init order** | ✅ Correct | ✅ Cleaned up, named routes added |

---

## File Map

```
output/
├── notification_service.dart     → drop into lib/services/
├── main.dart                     → replace lib/main.dart
├── supabase_service_additions.dart  → add getPendingProfilesStream() to lib/services/supabase_service.dart
└── admin_dashboard_patch.dart    → apply diff to lib/screens/admin_dashboard_screen.dart
```

---

## Step-by-Step Integration

### Step 1 — Replace notification_service.dart

Copy `output/notification_service.dart` to `lib/services/notification_service.dart`.

**What changed:**
- `_kNoticeChannel` and `_kReminderChannel` are now `const` objects defined at file level — channels are created up-front in `initLocalOnly()`, not on first use.
- `firebaseMessagingBackgroundHandler` re-creates them in the background isolate so they always exist.
- `_routeFromMessage()` centralises navigation logic for all three states (foreground tap, background tap, terminated launch).
- `printToken()` helper method — call it from a debug tap to print the FCM token to the console for testing.

---

### Step 2 — Replace main.dart

Copy `output/main.dart` to `lib/main.dart`.

**What changed:**
- Explicit comments on why each step is ordered the way it is.
- Named routes (`/notices`, `/exams`) wired into `MaterialApp` so notification taps navigate correctly.
- Status screens extracted into their own small widgets to keep `_ProfileRouterState.build()` readable.

---

### Step 3 — Add getPendingProfilesStream() to SupabaseService

Open `lib/services/supabase_service.dart` and add:

```dart
/// Real-time stream of pending profile approvals.
static Stream<List<Map<String, dynamic>>> getPendingProfilesStream() =>
    client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at');
```

> **Supabase Realtime prerequisite:** In your Supabase project → Database → Replication, enable the `profiles` table for realtime. Without this the stream falls back to one-time fetch behaviour.

---

### Step 4 — Patch admin_dashboard_screen.dart

Apply the diff from `output/admin_dashboard_patch.dart`:

1. Add `StreamSubscription<List<Map<String, dynamic>>>? _pendingSub;` field.
2. In `_subscribe()`, replace:
   ```dart
   // OLD
   SupabaseService.getPendingProfiles().then((data) {
     if (mounted) setState(() { _pendingCount = data.length; });
   });
   ```
   with:
   ```dart
   // NEW
   _pendingSub?.cancel();
   _pendingSub = SupabaseService.getPendingProfilesStream().listen((data) {
     if (mounted) setState(() => _pendingCount = data.length);
   });
   ```
3. In `dispose()`, add `_pendingSub?.cancel();`.

---

## How the Three FCM States Work

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FCM MESSAGE ARRIVES                          │
└───────────────────┬────────────────────────┬────────────────────────┘
                    │                        │
          ┌─────────▼──────────┐   ┌────────▼─────────┐
          │  App FOREGROUND    │   │  App BACKGROUND   │
          │                    │   │  or TERMINATED    │
          │ FCM suppresses OS  │   │                   │
          │ notification       │   │ OS shows system   │
          │                    │   │ notification      │
          │ FirebaseMessaging  │   │                   │
          │ .onMessage fires   │   └────────┬──────────┘
          │                    │            │
          │ → we call          │    User taps notification
          │ _showNoticeNotif() │            │
          └─────────┬──────────┘   ┌────────▼──────────┐
                    │              │ Was app killed?    │
                    │              │                    │
                    │         YES  │           NO       │
                    │    ┌─────────▼───┐   ┌───▼──────────────┐
                    │    │ TERMINATED  │   │ BACKGROUND TAP   │
                    │    │             │   │                  │
                    │    │ getInitial  │   │ onMessageOpened  │
                    │    │ Message()   │   │ App.listen()     │
                    │    └─────────┬───┘   └───┬──────────────┘
                    │              │            │
                    └──────────────┴────────────┘
                                   │
                          _routeFromMessage()
                                   │
                         Navigate to /notices
                         (or /exams etc. based
                          on message.data['type'])
```

---

## Background Handler Constraints

The `firebaseMessagingBackgroundHandler` function runs in a **separate Dart isolate**. This means:

- ❌ No access to `BuildContext` or widget tree
- ❌ No access to `Provider`, `setState`, or any running app state
- ✅ Can use `FlutterLocalNotificationsPlugin` (re-initialised in the isolate)
- ✅ Can call `Firebase` APIs (Firebase re-initialises automatically)
- ✅ Can use `http` for simple network calls
- ✅ Can read `SharedPreferences`

The handler must be a **top-level function** (not a method or closure) annotated with `@pragma('vm:entry-point')`.

---

## Testing FCM Push Notifications

### Method 1 — Firebase Console (easiest)
1. Run the app on a physical Android device (FCM doesn't work on emulator without Play Services).
2. Call `NotificationService().printToken()` from any button/tap — the token prints to the debug console.
3. Go to **Firebase Console → Engage → Messaging → Send your first message**.
4. Paste the token into *"Send test message"* → *"Add an FCM registration token"*.
5. Send — you should see the notification.

### Method 2 — cURL (for backend testing)
```bash
curl -X POST https://fcm.googleapis.com/v1/projects/YOUR_PROJECT_ID/messages:send \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "token": "YOUR_DEVICE_TOKEN",
      "notification": {
        "title": "Test Notice",
        "body": "This is a test push notification"
      },
      "data": {
        "type": "notice",
        "notice_id": "123"
      }
    }
  }'
```

### Method 3 — Supabase Edge Function (production)
Your existing `send-notice-notification` edge function iterates device tokens and calls FCM for each. Trigger it from Postman/cURL:
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/send-notice-notification \
  -H "Authorization: Bearer YOUR_SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title":"New Notice","description":"Test body","notice_id":"abc"}'
```

---

## Android Setup Checklist

- [ ] `google-services.json` in `android/app/`
- [ ] `classpath 'com.google.gms:google-services:...'` in `android/build.gradle`
- [ ] `apply plugin: 'com.google.gms.google-services'` in `android/app/build.gradle`
- [ ] `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` in `AndroidManifest.xml` (Android 13+)
- [ ] Realtime enabled for tables: `profiles`, `notices`, `notes`, `students`, `teachers`, `routines`, `exams`

---

## pubspec.yaml — Required Dependencies (already present in your project)

```yaml
dependencies:
  firebase_core: ^4.9.0
  firebase_messaging: ^16.2.2
  flutter_local_notifications: ^18.0.1
  timezone: ^0.10.1
  http: ^1.6.0
```

All dependencies are already in your `pubspec.yaml`. No additions needed.
