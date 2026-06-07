# CST Department Portal — Flutter Android App

A full-featured department portal app converted from your HTML/Supabase web app to Flutter.

---

## 📱 Features

| Feature | Student | Teacher | Admin |
|---|---|---|---|
| Login / Register | ✅ | ✅ | ✅ |
| View Notices | ✅ | ✅ | ✅ |
| Post / Edit Notices | ❌ | ✅ | ✅ |
| View Study Materials | ✅ | ✅ | ✅ |
| Upload / Edit Materials | ❌ | ✅ | ✅ |
| Class Routine | ✅ | ✅ | ✅ |
| Edit Routine | ❌ | ❌ | ✅ |
| Student Directory | ✅ | ✅ | ✅ |
| Manage Students | ❌ | ❌ | ✅ |
| Teacher Directory | ✅ | ✅ | ✅ |
| Manage Faculty | ❌ | ❌ | ✅ |
| Approve Registrations | ❌ | ❌ | ✅ |
| Student QR Code | ✅ (own) | ❌ | ✅ |
| My Profile | ✅ | ✅ | ✅ |

---

## 🛠️ Setup Instructions

### Step 1 — Install Flutter
Download and install Flutter SDK from https://flutter.dev/docs/get-started/install

### Step 2 — Configure Supabase

Open `lib/services/supabase_service.dart` and replace:

```dart
static const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
static const supabaseKey = 'YOUR_ANON_KEY';
```

Get these from your Supabase project → Settings → API.

### Step 3 — Supabase Database Tables

Make sure you have these tables in your Supabase project (same as your web app):

```sql
-- profiles (created on signup, pending approval)
create table profiles (
  id uuid primary key references auth.users(id),
  name text, email text, role text default 'student',
  roll text, registration text, contact text,
  semester text, shift text, session text,
  photo_url text, approved boolean default false,
  created_at timestamptz default now()
);

-- students
create table students (
  id uuid primary key default gen_random_uuid(),
  name text, email text, roll text, registration text,
  contact text, semester text, shift text, session text,
  photo_url text, created_at timestamptz default now()
);

-- notices
create table notices (
  id uuid primary key default gen_random_uuid(),
  title text not null, description text,
  priority text default 'normal',
  created_at timestamptz default now()
);

-- notes (study materials)
create table notes (
  id uuid primary key default gen_random_uuid(),
  title text not null, subject text, semester text,
  file_url text, created_at timestamptz default now()
);

-- routines
create table routines (
  id uuid primary key default gen_random_uuid(),
  semester text, day text, subject text,
  time text, room text, teacher text
);

-- teachers
create table teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null, designation text, subject text,
  email text, contact text
);
```

### Step 4 — RLS Policies (Supabase)

Enable RLS on all tables. Example policies:

```sql
-- Allow authenticated users to read everything
create policy "read_all" on notices for select using (auth.role() = 'authenticated');
create policy "read_all" on students for select using (auth.role() = 'authenticated');
-- etc.

-- For profiles: users can read/update their own
create policy "own_profile" on profiles for all using (auth.uid() = id);
```

### Step 5 — Run the App

```bash
cd cst_portal
flutter pub get
flutter run
```

To build a release APK:
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📁 Project Structure

```
lib/
├── main.dart                    # Entry point + auth routing
├── utils/
│   └── theme.dart               # Colors, theme, fonts
├── services/
│   └── supabase_service.dart    # All Supabase API calls
├── widgets/
│   └── common.dart              # Shared widgets (cards, buttons, etc.)
└── screens/
    ├── login_screen.dart        # Login + Register
    ├── student_home_screen.dart # Student bottom nav + home tab
    ├── admin_dashboard_screen.dart
    ├── teacher_dashboard_screen.dart
    ├── notices_screen.dart
    ├── notes_screen.dart        # Study materials
    ├── students_screen.dart
    ├── student_profile_screen.dart  # With QR code
    ├── routine_screen.dart
    ├── teachers_screen.dart
    ├── profile_screen.dart      # My Profile
    └── approvals_screen.dart    # Admin approvals
```

---

## 🎨 Design

- **Theme**: Dark (Netflix-inspired) matching your web app
- **Primary color**: `#FF2E44` (red accent)
- **Background**: `#0A0D14`
- **Font**: Google Fonts (Inter + Poppins)

---

## 📦 Key Dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Backend (auth, database) |
| `google_fonts` | Poppins + Inter fonts |
| `qr_flutter` | QR code generation |
| `shimmer` | Loading skeletons |
| `url_launcher` | Open file download links |
| `cached_network_image` | Student photos |
| `image_picker` | Profile photo upload |
