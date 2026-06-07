// ── Supabase Edge Function: resize-profile-photos ───────────────────────────
// Scans existing profile photos in the `student-photos` bucket and reports
// their sizes for a dry-run preview.
//
// Deploy:  supabase functions deploy resize-profile-photos
// Invoke:
//   curl -X POST <PROJECT_REF>.functions.supabase.co/resize-profile-photos \
//     -H "Authorization: Bearer <ANON_KEY>" \
//     -H "Content-Type: application/json" \
//     -d '{}'
//
// Parameters (JSON body):
//   userId     – if set, scan only this specific user's photos
// ──────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Configuration ───────────────────────────────────────────────────────────
const BUCKET = "student-photos";

// ── Types ───────────────────────────────────────────────────────────────────
interface RequestBody {
  userId?: string;
}

interface FileEntry {
  path: string;
  size: number;
  contentType: string | null;
  location: "root" | "userFolder";
  userId?: string;
}

interface ResponseBody {
  success: boolean;
  files: FileEntry[];
  totalFiles: number;
  totalSizeBytes: number;
  userFolders: string[];
  elapsedMs: number;
  message: string;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/** Format bytes for human-readable output. */
function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function isImageFile(name: string): boolean {
  return /\.(jpe?g|png|webp|gif|bmp|tiff?|heic|heif)$/i.test(name);
}

// ── Main processing logic ───────────────────────────────────────────────────

async function scanAll(
  supabase: ReturnType<typeof createClient>,
  specificUserId?: string,
): Promise<ResponseBody> {
  const files: FileEntry[] = [];
  const startTime = Date.now();

  // ── Step 1: List bucket root ──────────────────────────────────────────
  const { data: rootItems, error: rootErr } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 1000 });

  if (rootErr) {
    return {
      success: false,
      files: [],
      totalFiles: 0,
      totalSizeBytes: 0,
      userFolders: [],
      elapsedMs: Date.now() - startTime,
      message: `Failed to list bucket root: ${rootErr.message}`,
    };
  }

  // Separate root-level files from user folders
  const rootFiles = (rootItems ?? []).filter((f) => f.id !== null);
  const userDirs = (rootItems ?? []).filter((f) => f.id === null);
  const userFolderNames = userDirs.map((d) => d.name);

  // ── Step 2: Scan root-level image files ───────────────────────────────
  for (const f of rootFiles) {
    if (isImageFile(f.name)) {
      files.push({
        path: f.name,
        size: f.metadata?.size ?? 0,
        contentType: f.metadata?.mimetype ?? null,
        location: "root",
      });
    }
  }

  // ── Step 3: Scan user subdirectories ──────────────────────────────────
  const dirsToScan = specificUserId
    ? userDirs.filter((d) => d.name === specificUserId)
    : userDirs;

  for (const dir of dirsToScan) {
    const uid = dir.name;
    const { data: userFiles } = await supabase.storage
      .from(BUCKET)
      .list(uid, { limit: 1000 });

    if (!userFiles) continue;

    for (const f of userFiles) {
      if (f.id !== null && isImageFile(f.name)) {
        files.push({
          path: `${uid}/${f.name}`,
          size: f.metadata?.size ?? 0,
          contentType: f.metadata?.mimetype ?? null,
          location: "userFolder",
          userId: uid,
        });
      }
    }
  }

  // Sort by path
  files.sort((a, b) => a.path.localeCompare(b.path));

  const totalFiles = files.length;
  const totalSizeBytes = files.reduce((sum, f) => sum + f.size, 0);

  // ── Build summary ─────────────────────────────────────────────────────
  const rootCount = files.filter((f) => f.location === "root").length;
  const folderCount = files.filter((f) => f.location === "userFolder").length;
  const sizeFormatted = formatBytes(totalSizeBytes);

  const userFolderStr = userFolderNames.length > 0
    ? `\n  User folders: ${userFolderNames.length} (${userFolderNames.join(", ")})`
    : "";

  const detailLines = files.map((f) => {
    const tag = f.location === "root" ? "[ROOT]" : `[USER]`;
    const type = f.contentType ?? "unknown";
    return `  ${tag} ${f.path.padEnd(60)} ${formatBytes(f.size).padStart(10)}  ${type}`;
  }).join("\n");

  const message =
    `Found ${totalFiles} image(s) (${sizeFormatted} total): ` +
    `${rootCount} at root, ${folderCount} in user folders.` +
    userFolderStr +
    `\n${detailLines}`;

  return {
    success: true,
    files,
    totalFiles,
    totalSizeBytes,
    userFolders: userFolderNames,
    elapsedMs: Date.now() - startTime,
    message,
  };
}

// ── HTTP Handler ────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  try {
    let body: RequestBody = {};
    if (req.method === "POST") {
      try { body = await req.json(); } catch {
        return new Response(
          JSON.stringify({ success: false, error: "Invalid JSON body" }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing env vars" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
    });

    const result = await scanAll(supabase, body.userId);
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
