#!/usr/bin/env node

/**
 * Resize Existing Profile Photos
 *
 * Scans the `student-photos` Supabase Storage bucket and resizes every
 * profile photo to 512px max dimension (PNG), matching the resize that
 * new uploads now receive via the Flutter app fix.
 *
 * Usage:
 *   node index.js                     # resize all photos
 *   node index.js --dry-run           # preview without modifying
 *
 * Environment variables (via .env):
 *   SUPABASE_URL               – your Supabase project URL
 *   SUPABASE_SERVICE_ROLE_KEY  – Service Role key (admin access)
 *
 * Get your Service Role key:
 *   Supabase Dashboard → Settings → API → `service_role_key`
 */

import "dotenv/config";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import readline from "node:readline/promises";

// ── Configuration ───────────────────────────────────────────────────────────
const MAX_DIMENSION = 512; // px – same as _resizeForUpload in the Flutter app
const BUCKET = "student-photos";
const FILE_PREFIX = "profile_"; // only files starting with this get processed

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const isDryRun = process.argv.includes("--dry-run");

// ── Validate environment ────────────────────────────────────────────────────
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env file.");
  console.error("");
  console.error("   Create a .env file with:");
  console.error("   SUPABASE_URL=https://cqtbntuyornjwqqzwrdy.supabase.co");
  console.error("   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key");
  console.error("");
  console.error("   Get your Service Role key from:");
  console.error("   Supabase Dashboard → Settings → API → service_role_key");
  process.exit(1);
}

// ── Supabase client (service role = bypasses RLS) ───────────────────────────
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ── Stats ───────────────────────────────────────────────────────────────────
let stats = { downloaded: 0, resized: 0, skipped: 0, errors: 0 };

// ── Helpers ─────────────────────────────────────────────────────────────────

/** Determine if a file name looks like a profile photo we should process. */
function isProfilePhoto(name) {
  return name.startsWith(FILE_PREFIX);
}

/** Determine if a content-type indicates a raster image we can process. */
function isImage(contentType) {
  if (!contentType) return true; // try anyway if unknown
  return /^image\/(jpeg|png|webp|gif|bmp|tiff|heic|heif)$/i.test(contentType);
}

/** Resize image buffer to at most MAX_DIMENSION on the longest side → PNG. */
async function resizeImage(buffer) {
  return sharp(buffer)
    .resize(MAX_DIMENSION, MAX_DIMENSION, {
      fit: "inside", // maintain aspect ratio, no cropping
      withoutEnlargement: true, // don't upscale small images
    })
    .png() // lossless, preserves alpha – matches _resizeForUpload
    .toBuffer();
}

/** Format bytes for human-readable output. */
function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Format size change percentage. Negative = smaller, positive = larger. */
function formatSavings(original, resized) {
  const pct = ((1 - resized / original) * 100).toFixed(1);
  if (pct.startsWith("-")) return `+${pct.substring(1)}% larger`;
  return `${pct}% smaller`;
}

function log(...args) {
  console.log(...args);
}

function warn(...args) {
  console.warn("⚠️ ", ...args);
}

function error(...args) {
  console.error("❌ ", ...args);
}

// ── Confirmation prompt ─────────────────────────────────────────────────────

async function confirmProceed(fileCount) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    const answer = await rl.question(
      `\n❗ This will resize and replace ${fileCount} file(s) in the "${BUCKET}" bucket.\n` +
        `   This operation cannot be undone automatically.\n` +
        `   Proceed? (y/N) `,
    );
    return answer.toLowerCase() === "y" || answer.toLowerCase() === "yes";
  } finally {
    rl.close();
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  log(`\n📸 Profile Photo Migration`);
  log(`   Bucket:        ${BUCKET}`);
  log(`   Max dimension: ${MAX_DIMENSION}px`);
  log(`   Format:        PNG`);
  log(`   Dry run:       ${isDryRun ? "YES (no changes will be made)" : "NO"}`);
  log("");

  // ── 1. List all user directories ───────────────────────────────────────
  log("🔍 Listing user directories…");
  const { data: folders, error: foldersErr } = await supabase.storage
    .from(BUCKET)
    .list({ limit: 1000 });

  if (foldersErr) {
    error(`Failed to list bucket root: ${foldersErr.message}`);
    process.exit(1);
  }

  if (!folders || folders.length === 0) {
    log("   (empty bucket – nothing to do)");
    return;
  }

  // Folders are items with `id: null` in Supabase Storage listing
  const userDirs = folders.filter((f) => f.id === null);
  log(`   Found ${userDirs.length} user director${userDirs.length === 1 ? "y" : "ies"}.`);

  // ── 2. Count files to process (for confirmation) ───────────────────────
  let totalFiles = 0;
  const userFileCounts = [];

  for (const dir of userDirs) {
    const userId = dir.name;
    const { data: files } = await supabase.storage
      .from(BUCKET)
      .list(userId, { limit: 1000 });

    if (!files) continue;

    const count = files.filter(
      (f) => f.id !== null && isProfilePhoto(f.name),
    ).length;
    if (count > 0) {
      userFileCounts.push({ userId, count });
      totalFiles += count;
    }
  }

  if (totalFiles === 0) {
    log("\n✅ No profile photos found to resize.");
    return;
  }

  log(`   ${totalFiles} profile photo(s) across ${userFileCounts.length} user(s).`);

  // ── 3. Confirmation (skip in dry-run) ──────────────────────────────────
  if (!isDryRun) {
    const ok = await confirmProceed(totalFiles);
    if (!ok) {
      log("\n   Aborted. No changes were made.");
      return;
    }
    log("");
  }

  // ── 4. Process each user directory ─────────────────────────────────────
  for (const [dirIndex, dir] of userDirs.entries()) {
    const userId = dir.name;
    log(`📁 [${dirIndex + 1}/${userDirs.length}] User: ${userId}`);

    const { data: files, error: filesErr } = await supabase.storage
      .from(BUCKET)
      .list(userId, { limit: 1000 });

    if (filesErr) {
      error(`Failed to list files for ${userId}: ${filesErr.message}`);
      stats.errors++;
      continue;
    }

    const profilePhotos = files.filter(
      (f) => f.id !== null && isProfilePhoto(f.name),
    );

    if (profilePhotos.length === 0) {
      continue;
    }

    // ── 5. Process each file ────────────────────────────────────────────
    for (const file of profilePhotos) {
      const filePath = `${userId}/${file.name}`;

      // Check if the metadata suggests a supported image type
      if (!isImage(file.metadata?.mimetype)) {
        log(`   ⏭️  ${filePath} (unsupported type: ${file.metadata?.mimetype ?? "unknown"})`);
        stats.skipped++;
        continue;
      }

      try {
        // ── Download ──────────────────────────────────────────────────
        const { data: downloadData, error: downloadErr } = await supabase.storage
          .from(BUCKET)
          .download(filePath);

        if (downloadErr || !downloadData) {
          error(`Download failed: ${filePath} — ${downloadErr?.message ?? "no data"}`);
          stats.errors++;
          continue;
        }

        const originalBuffer = Buffer.from(await downloadData.arrayBuffer());
        const originalSize = originalBuffer.length;
        stats.downloaded++;

        log(`   📥 ${filePath} (${formatBytes(originalSize)})`);

        // ── Resize ────────────────────────────────────────────────────
        let resizedBuffer;
        try {
          resizedBuffer = await resizeImage(originalBuffer);
        } catch (resizeErr) {
          warn(`${filePath} could not be decoded as an image: ${resizeErr.message}`);
          stats.skipped++;
          continue;
        }

        const resizedSize = resizedBuffer.length;
        stats.resized++;

        log(`      → ${formatBytes(resizedSize)} (${formatSavings(originalSize, resizedSize)})`);

        // ── Upload (replace) ──────────────────────────────────────────
        if (isDryRun) {
          log(`      🏁 [DRY RUN] Would replace with resized PNG.`);
          continue;
        }

        // Strategy: upload new file first, then remove old one.
        // This way, if the upload fails, the original is never lost.
        const newPath = filePath; // same path – replaces in place

        const { error: uploadErr } = await supabase.storage
          .from(BUCKET)
          .upload(newPath, resizedBuffer, {
            contentType: "image/png",
            upsert: true,
          });

        if (uploadErr) {
          error(`Upload failed for ${filePath}: ${uploadErr.message}`);
          stats.errors++;
          continue;
        }

        log(`      ✅ Replaced with resized PNG.`);
      } catch (err) {
        error(`Unexpected error processing ${filePath}: ${err.message}`);
        stats.errors++;
      }
    }
  }

  // ── Summary ────────────────────────────────────────────────────────────
  log("\n" + "=".repeat(50));
  log("📊 Summary");
  log(`   Downloaded:  ${stats.downloaded}`);
  log(`   Resized:     ${stats.resized}`);
  log(`   Skipped:     ${stats.skipped}`);
  log(`   Errors:      ${stats.errors}`);
  log(`   Dry run:     ${isDryRun}`);
  log("=".repeat(50));

  if (!isDryRun && stats.resized > 0) {
    log("\n✅ Migration complete! Users may need to clear their app cache");
    log("   or re-open the app to see the updated photos.");
  }

  if (isDryRun && stats.resized > 0) {
    log("\n   Run without --dry-run to apply these changes.");
  }
}

main().catch((err) => {
  error("Fatal:", err);
  process.exit(1);
});
