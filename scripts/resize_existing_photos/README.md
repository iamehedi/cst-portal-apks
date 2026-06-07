# Retroactive Profile Photo Resizer

Resizes all existing profile photos in the `student-photos` Supabase Storage bucket to 512px max dimension (PNG). This retroactively applies the same resize that new uploads now get via the Flutter app fix.

## Prerequisites

- Node.js 18+
- Supabase **Service Role Key** (from Supabase Dashboard → Settings → API → `service_role_key`)

## Setup

```bash
cd scripts/resize_existing_photos
npm install
```

Create a `.env` file:

```env
SUPABASE_URL=https://cqtbntuyornjwqqzwrdy.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
```

> ⚠️ **Keep this key private.** Never commit `.env` to version control.

## Run

```bash
npm start
```

This will:

1.  List all folders in the `student-photos` bucket (one per user)
2.  For each user, find all `profile_*` image files
3.  Download each, resize to 512×512 (max, maintaining aspect ratio)
4.  Re-upload as PNG, replacing the original
5.  Print progress as it goes

## What it resizes

Only files matching `profile_*` inside user ID subdirectories in the `student-photos` bucket. Other files are left untouched.

## Dry run

To preview what would be processed without actually modifying anything, add `--dry-run`:

```bash
npm start -- --dry-run
```
