-- Migration: Add user_id columns to notices and notes tables
-- This allows the push notification Edge Function to exclude the
-- posting admin from receiving their own notification.
--
-- Run this in Supabase → SQL Editor.
-- Safe to run multiple times (IF NOT EXISTS / IF EXISTS guards).

-- ── Add user_id to notices ──────────────────────────────────────────────────
ALTER TABLE public.notices
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── Add user_id to notes ────────────────────────────────────────────────────
ALTER TABLE public.notes
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── Create index for faster webhook queries ──────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_notices_created_at ON public.notices (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_upload_date ON public.notes (upload_date DESC);
