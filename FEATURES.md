# CST Portal — Complete Feature List

> A Flutter + Firebase + Supabase educational institute portal app for the Computer Science & Technology (CST) department.

---

## 1. Authentication & Registration

| Feature | Details |
|---------|---------|
| **Email/Password Sign In** | Supabase Auth with email + password login |
| **New User Registration** | Name, email, password, role (Student/Teacher/Admin), semester, subject, designation |
| **Role-based Routing** | After login, users land on different dashboards based on role |
| **Pending Approval System** | New registrations require admin approval before access is granted |
| **Reject + Delete** | Admin can reject a pending user — deletes auth user entirely, freeing the email for re-registration |
| **Logout** | Secure sign-out from all screens |

---

## 2. Admin Dashboard

| Feature | Details |
|---------|---------|
| **Overview Tab** | Dashboard home with quick stats and pending approval count |
| **Students Tab** | Full student directory with CRUD operations |
| **Routine Tab** | Manage class routine slots for all semesters |
| **Notes Tab** | Upload, edit, delete study materials (PDF, image, markdown) |
| **Notices Tab** | Publish, edit, delete notices with optional file attachments |
| **Profile Approval** | Real-time stream of pending profiles — approve or reject with one tap |
| **User Deletion** | Delete user profile + auth account via Supabase Edge Function |
| **Student Management** | Add/edit/delete student records (name, roll, registration, semester, shift, session, email, contact) |
| **Teacher Management** | Add/edit/delete teacher records (name, designation, subject, phone) |
| **Exam Routine Management** | Create/edit/delete exam schedules (subject, date, time, room, exam type, semester) |

---

## 3. Teacher Dashboard

| Feature | Details |
|---------|---------|
| **Home Tab** | Greeting + quick stats overview |
| **Notes Tab** | Upload and manage study materials (full CRUD) |
| **Notices Tab** | Publish and manage notices (full CRUD) |

---

## 4. Student Home Screen

| Feature | Details |
|---------|---------|
| **Home Tab** | Greeting, semester badge, quick-access cards to Notices, Notes, Routine, Teachers |
| **Notices Tab** | View all published notices |
| **Notes Tab** | View study materials filtered by semester |
| **Routine Tab** | View class routine for own semester |
| **Profile Tab** | View and edit own profile |

---

## 5. Notices System

| Feature | Details |
|---------|---------|
| **Real-time Updates** | Supabase Realtime stream — notices appear instantly when published |
| **Auto-refresh** | Periodic fallback refresh for network interruptions |
| **Pull-to-Refresh** | Manual swipe-to-refresh gesture |
| **File Attachments** | Admin/Teacher can attach files (PDF, images) to notices via Supabase Storage |
| **Attachment Viewing** | Students can open/view attachments directly |
| **Create/Edit/Delete** | Full CRUD for authorized users (admin, teacher) |
| **Timeline Layout** | Timeline dots + lines visual layout for notice list |

---

## 6. Notes (Study Materials)

| Feature | Details |
|---------|---------|
| **File Upload** | Admin/Teacher uploads PDF, images, or text/markdown notes |
| **Semester Filtering** | Filter notes by semester (1st–8th) |
| **Search** | Search notes by title or subject |
| **Real-time Updates** | Supabase Realtime stream — notes appear instantly |
| **3-layer Live Update** | Realtime stream + 20-second auto-refresh + pull-to-refresh |
| **In-app Preview** | Preview notes directly in the app: image preview, markdown rendering, PDF card |
| **Open Externally** | Open PDFs/files in external apps via url_launcher |
| **Download to Device** | Download files to `Downloads/CST Portal/` folder via native MethodChannel + MediaStore (Android 10+) |
| **Note Metadata** | Title, subject, semester badge, upload date, teacher name |
| **Create/Edit/Delete** | Full CRUD for authorized users |
| **File Size Validation** | 50 MB max file size limit |

---

## 7. Class Routine

| Feature | Details |
|---------|---------|
| **Weekly Timetable** | Day-by-day grid layout (Monday–Thursday + Sunday) |
| **Semester Filtering** | View routine for any semester (1–8) |
| **Period Details** | Subject, subject code, teacher, room for each period slot |
| **Real-time Updates** | Supabase Realtime stream |
| **Admin CRUD** | Admin can add/edit/delete routine slots |
| **Semester Badge** | Visual semester indicator |

---

## 8. Exam Routine

| Feature | Details |
|---------|---------|
| **Exam Schedule View** | List of upcoming exams with date, time, room, type |
| **Semester Filtering** | Filter exams by semester |
| **Real-time Updates** | Supabase Realtime stream |
| **Admin CRUD** | Admin can add/edit/delete exam entries |
| **Exam Reminder Toggle** | Enable/disable 24-hour-before exam reminders |

---

## 9. Student Directory

| Feature | Details |
|---------|---------|
| **Student List** | View all students with name, roll, semester, shift, session |
| **Semester Filtering** | Filter by semester |
| **Search** | Search students by name or roll |
| **Student Profile View** | Tap a student to see detailed profile |
| **Real-time Updates** | Supabase Realtime stream |
| **Privacy Controls** | Students see limited peer info (semester/shift/session/roll only); reg/email/contact visible to admin/teacher |

---

## 10. Teacher Directory

| Feature | Details |
|---------|---------|
| **Teacher List** | View all teachers with name, designation, subject |
| **Real-time Updates** | Supabase Realtime stream |
| **Teacher Profile View** | Tap a teacher to see full details |
| **Admin CRUD** | Admin can add/edit/delete teacher records |

---

## 11. Profile System

| Feature | Details |
|---------|---------|
| **Profile Photo** | Upload/change profile photo (stored in Supabase Storage `student-photos` bucket) |
| **QR Code** | Auto-generated QR code with student's name, roll, email, semester |
| **Profile Editing** | Students can edit their own profile (name, semester, shift, session, roll, contact) |
| **Profile Card** | Clean card layout with photo, name, email, role badge, semester badge |
| **Theme Picker** | Switch between Dark, Light, and System themes directly from profile |
| **App Version Display** | Shows current app version from package_info_plus |

---

## 12. Notifications & Reminders

| Feature | Details |
|---------|---------|
| **Push Notifications** | Firebase Cloud Messaging (FCM) for admin-published notices/notes |
| **Foreground Notifications** | Local notification popup when app is open |
| **Background Notifications** | Notification delivered when app is in background |
| **Terminated State** | Notification tap opens app and routes to correct screen |
| **Notification Channels** | Separate Android channels: "Important Notices" and "Exam & Class Reminders" |
| **Class Reminders** | Toggle on/off — schedules weekly reminders before each class period |
| **Exam Reminders** | Toggle on/off — schedules reminders 24 hours before each exam |
| **Custom Lead Time** | Configurable minutes-before for class reminders (default: 15 min) |
| **Auto-reschedule** | Reminders automatically reschedule on app launch (covers device reboot/OS alarm clear) |
| **Permission Request** | Notification permission requested on Android 13+ via Firebase |
| **Exact Alarms** | Uses `SCHEDULE_EXACT_ALARM` for precise reminder timing |

---

## 13. Theming & UI

| Feature | Details |
|---------|---------|
| **Dark Theme** | "CSTIAN DARK" — YouTube Music-inspired deep dark theme with red accent |
| **Light Theme** | "CSTIAN WHITE" — Warm off-white theme with Material Red 600 accent |
| **System Theme** | Follows device dark/light mode automatically |
| **Theme Persistence** | Selected theme saved in SharedPreferences |
| **Animated Transitions** | iOS-style Cupertino push routes, fade+slide tab switching |
| **Responsive Layout** | Adapts to small (<360px), medium (360–600px), and large (>600px) screens |
| **Staggered Animations** | List items animate in with staggered delays |
| **Shimmer Loading** | Shimmer effect while content loads |
| **Emoji Support** | NotoColorEmoji font for rendering emoji in all themes |

---

## 14. Error Handling & Reliability

| Feature | Details |
|---------|---------|
| **Error Boundary** | Global FlutterError.onError catches and displays crash info (debug) / restart prompt (release) |
| **Version Check** | Checks for app updates on launch (via package_info_plus) |
| **Mounted Guards** | Async operations check `mounted` before setState/context usage |
| **Non-blocking FCM** | Device token save failure is caught and logged, doesn't crash the app |
| **FCM Timeout** | 10-second timeout on getToken() to prevent release build hangs |
| **Stream Cleanup** | All stream subscriptions cancelled in dispose() |

---

## 15. Storage & File Management

| Feature | Details |
|---------|---------|
| **Student Photos** | Supabase Storage bucket `student-photos` — uploaded by students for profile pictures |
| **Note Files** | Supabase Storage bucket `notes-files` — PDFs, images uploaded with notes |
| **Notice Attachments** | Supabase Storage bucket `notice-attachments` — files attached to notices |
| **File Download** | Native MethodChannel saves to public `Downloads/CST Portal/` folder using MediaStore API |
| **50 MB Limit** | Server-side file size validation before upload |

---

## 16. Android Configuration

| Feature | Details |
|---------|---------|
| **APK Splits** | Per-ABI APK splits (armeabi-v7a, arm64-v8a, x86_64) for smaller download sizes |
| **ProGuard/R8** | Code minification + resource shrinking enabled for release builds |
| **Custom ProGuard Rules** | Keep rules for Firebase, Supabase, Kotlin Serialization, OkHttp, url_launcher |
| **Package Visibility** | `<queries>` block for url_launcher on Android 11+ |
| **Notification Permission** | `POST_NOTIFICATIONS` declared for Android 13+ |
| **Granular Storage** | `READ_MEDIA_IMAGES` for Android 13+, `READ_EXTERNAL_STORAGE` with maxSdkVersion=32 for older |
| **Exact Alarm Permission** | `SCHEDULE_EXACT_ALARM` declared for precise reminders |
| **Portrait Lock** | Locked to portrait orientation |

---

## 17. Backend (Supabase)

| Feature | Details |
|---------|---------|
| **Row Level Security (RLS)** | RLS policies on all tables — admin write access, public read access |
| **Realtime Subscriptions** | Enabled on students, teachers, notes, notices, exams, routine tables |
| **Supabase Edge Function** | `delete-user` function for fully removing auth users |
| **Database Trigger** | Auto-creates profile from `raw_user_meta_data` on user registration |
| **Storage Buckets** | 3 public buckets with per-user upload paths |
| **Device Token Management** | FCM tokens stored per-user for targeted push notifications |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x (Dart) |
| **Backend** | Supabase (PostgreSQL + Auth + Storage + Realtime + Edge Functions) |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **Local Notifications** | flutter_local_notifications |
| **State Management** | Provider |
| **Fonts** | Google Fonts (Poppins + Inter) |
| **Animations** | flutter_animate |
