-- Migration: Add note_content column to notes table
-- This allows storing text/markdown content directly in notes for in-app preview.
--
-- Run this in Supabase → SQL Editor.
-- Safe to run multiple times (IF NOT EXISTS guard).

ALTER TABLE public.notes
  ADD COLUMN IF NOT EXISTS note_content text;

