// ── Supabase Edge Function: send-notice-notification ─────────────────────────
// Deploy with: supabase functions deploy send-notice-notification
//
// Sends FCM v1 push notifications when a notice or note is posted.
// Trigger: Supabase Database Webhook on INSERT into `notices` and `notes` tables.
//
// ── Setup ────────────────────────────────────────────────────────────────────
// 1. In Firebase Console → Project Settings → Service accounts → Generate
//    new private key. Download the JSON file.
//
// 2. Set the service account JSON as a Supabase secret:
//    supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='{...}'
//
// 3. Deploy:
//    supabase functions deploy send-notice-notification
//
// 4. Create database webhooks in Supabase Dashboard → Database → Webhooks:
//    Webhook 1:
//      - Name: notice-push-notification
//      - Table: notices
//      - Events: INSERT
//      - Type: Supabase Edge Function
//      - Edge Function: send-notice-notification
//      - Method: POST
//    Webhook 2:
//      - Name: notes-push-notification
//      - Table: notes
//      - Events: INSERT
//      - Type: Supabase Edge Function
//      - Edge Function: send-notice-notification
//      - Method: POST
// ──────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { GoogleAuth } from "npm:google-auth-library@^9.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── FCM token cache ─────────────────────────────────────────────────────────
let _cachedToken: string | null = null;
let _tokenExpiry = 0;

async function getFcmAccessToken(): Promise<string> {
  if (_cachedToken && Date.now() < _tokenExpiry - 300_000) {
    return _cachedToken;
  }

  const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountJson) {
    throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON not set");
  }

  const serviceAccount = JSON.parse(serviceAccountJson);
  const auth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: "https://www.googleapis.com/auth/firebase.messaging",
  });

  const client = await auth.getClient();
  const token = await client.getAccessToken();

  _cachedToken = token.token as string;
  _tokenExpiry = Date.now() + 55 * 60 * 1000;
  return _cachedToken;
}

async function sendFcmV1(
  deviceToken: string,
  title: string,
  body: string,
  projectId: string,
  notifType: string,
  staleTokens: string[],
): Promise<boolean> {
  try {
    const accessToken = await getFcmAccessToken();

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            notification: {
              title,
              body: body.substring(0, 200),
            },
            android: {
              notification: {
                sound: "default",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
            data: {
              type: notifType,
            },
          },
        }),
      },
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `[FCM] Error for token ${deviceToken.substring(0, 20)}...: status=${response.status} body=${errorText}`,
      );
      if (response.status === 404 || response.status === 410) {
        staleTokens.push(deviceToken);
        console.warn(`[FCM] Stale token queued: ${deviceToken.substring(0, 20)}...`);
      }
      return false;
    }
    return true;
  } catch (err) {
    console.error(`[FCM] Request exception: ${err}`);
    return false;
  }
}

// ── Main handler ────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  try {
    // ── Step 1: Read raw body ────────────────────────────────────────────
    let rawBody: string;
    try {
      rawBody = await req.text();
      console.log(`[INIT] Method=${req.method} Content-Type=${req.headers.get("content-type")}`);
      console.log(`[INIT] Raw body: ${rawBody}`);
    } catch (err) {
      console.error(`[INIT] Failed to read request body: ${err}`);
      return new Response(
        JSON.stringify({ error: "Failed to read request body", details: String(err) }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Step 2: Parse JSON ───────────────────────────────────────────────
    let rawPayload: Record<string, unknown>;
    try {
      rawPayload = JSON.parse(rawBody);
      console.log(`[PARSE] Parsed keys: [${Object.keys(rawPayload).join(", ")}]`);
      console.log(`[PARSE] Full payload: ${JSON.stringify(rawPayload)}`);
    } catch (err) {
      console.error(`[PARSE] JSON parse failed: ${err}`);
      return new Response(
        JSON.stringify({ error: "Invalid JSON", received: rawBody.substring(0, 500) }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Step 3: Extract record from webhook payload ──────────────────────
    // Supabase Database Webhook format:
    // {
    //   "type": "INSERT",
    //   "table": "notices",
    //   "schema": "public",
    //   "record": { "id": "...", "title": "...", ... },
    //   "old_record": null
    // }
    const record = rawPayload.record as Record<string, unknown> | undefined;
    const table = rawPayload.table as string | undefined;

    console.log(`[EXTRACT] table=${table}, record exists=${!!record}`);

    if (record) {
      console.log(`[EXTRACT] record keys: [${Object.keys(record).join(", ")}]`);
      console.log(`[EXTRACT] record.id=${record.id}`);
      console.log(`[EXTRACT] record.title=${record.title}`);
      console.log(`[EXTRACT] record.note_title=${record.note_title}`);
      console.log(`[EXTRACT] record.description=${record.description}`);
      console.log(`[EXTRACT] record.subject=${record.subject}`);
      console.log(`[EXTRACT] record.user_id=${record.user_id}`);
    }

    if (!record || !table) {
      console.error(`[EXTRACT] Missing record or table. record=${!!record}, table=${table}`);
      return new Response(
        JSON.stringify({
          error: "Expected webhook payload with 'record' and 'table' fields",
          received_keys: Object.keys(rawPayload),
          received_payload: rawPayload,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Step 4: Extract fields ───────────────────────────────────────────
    const isNotes = table === "notes";
    const title = (record.title ?? record.note_title ?? "New update") as string;
    const description = (record.description ?? record.subject ?? "") as string;
    const notifType = isNotes ? "note" : "notice";
    const excludeUserId = (record.user_id as string) ?? undefined;

    console.log(`[NOTIFY] table=${table} title="${title}" type=${notifType} excludeUserId=${excludeUserId}`);

    if (!title || title.trim() === "") {
      console.error(`[NOTIFY] Title is empty`);
      return new Response(JSON.stringify({ error: "Title is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── Step 5: Check service account ────────────────────────────────────
    const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
    if (!serviceAccountJson) {
      console.error(`[CONFIG] GOOGLE_SERVICE_ACCOUNT_JSON not set`);
      return new Response(
        JSON.stringify({ error: "Server config error: GOOGLE_SERVICE_ACCOUNT_JSON not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    let projectId: string;
    try {
      projectId = JSON.parse(serviceAccountJson).project_id;
      console.log(`[CONFIG] projectId=${projectId}`);
    } catch (err) {
      console.error(`[CONFIG] Failed to parse service account JSON: ${err}`);
      return new Response(
        JSON.stringify({ error: "Invalid GOOGLE_SERVICE_ACCOUNT_JSON" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Step 6: Query device tokens ──────────────────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error(`[CONFIG] Missing Supabase env vars. URL=${!!supabaseUrl} KEY=${!!supabaseServiceKey}`);
      return new Response(
        JSON.stringify({ error: "Missing Supabase environment variables" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let query = supabase
      .from("device_tokens")
      .select("device_token, user_id");

    if (excludeUserId) {
      query = query.neq("user_id", excludeUserId);
      console.log(`[TOKENS] Excluding user_id=${excludeUserId}`);
    }

    const { data: tokens, error } = await query;

    if (error) {
      console.error(`[TOKENS] Query error: ${error.message}`);
      return new Response(
        JSON.stringify({ error: "Failed to fetch device tokens", details: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(`[TOKENS] Found ${tokens?.length ?? 0} device token(s)`);

    if (!tokens || tokens.length === 0) {
      console.log(`[TOKENS] No tokens to send to`);
      return new Response(
        JSON.stringify({ sent: 0, reason: "no_tokens" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Step 7: Build notification ───────────────────────────────────────
    const defaultBody = isNotes
      ? "New study material uploaded on CST Portal"
      : "New notice posted on CST Portal";

    const notificationBody =
      description && description.trim() !== ""
        ? description.trim().substring(0, 200)
        : defaultBody;

    console.log(`[SEND] Sending "${title}" — "${notificationBody}" to ${tokens.length} device(s)`);

    // ── Step 8: Send to each device ──────────────────────────────────────
    let sentCount = 0;
    let failedCount = 0;
    const staleTokens: string[] = [];

    for (const tokenData of tokens as { device_token: string }[]) {
      const token = tokenData.device_token;
      if (!token) continue;

      const ok = await sendFcmV1(
        token,
        title,
        notificationBody,
        projectId,
        notifType,
        staleTokens,
      );

      if (ok) sentCount++;
      else failedCount++;
    }

    // ── Step 9: Clean up stale tokens ────────────────────────────────────
    let removedStale = 0;
    if (staleTokens.length > 0) {
      const { error: deleteError, count } = await supabase
        .from("device_tokens")
        .delete()
        .in("device_token", staleTokens);
      if (deleteError) {
        console.error(`[CLEANUP] Error: ${deleteError.message}`);
      } else {
        removedStale = count ?? staleTokens.length;
        console.log(`[CLEANUP] Removed ${removedStale} stale token(s)`);
      }
    }

    console.log(
      `[DONE] sent=${sentCount} failed=${failedCount} stale_removed=${removedStale}`,
    );

    return new Response(
      JSON.stringify({
        sent: sentCount,
        failed: failedCount,
        stale_removed: removedStale,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (topLevelErr) {
    // ── Catch-all: log any unhandled error ───────────────────────────────
    console.error(`[FATAL] Unhandled error: ${topLevelErr}`);
    console.error(`[FATAL] Stack: ${topLevelErr instanceof Error ? topLevelErr.stack : "no stack"}`);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: String(topLevelErr),
        stack: topLevelErr instanceof Error ? topLevelErr.stack : undefined,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
