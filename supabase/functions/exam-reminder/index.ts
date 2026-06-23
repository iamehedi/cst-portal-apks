// ── Supabase Edge Function: exam-reminder ───────────────────────────────────
// Deploy with: supabase functions deploy exam-reminder
//
// This function:
// 1. Runs automatically every day at 8:00 AM via Deno.cron
// 2. Can also be invoked manually via HTTP (e.g., for testing)
// 3. Queries tomorrow's exams from the database
// 4. Sends FCM push notifications to all registered device tokens
//
// ── Setup ────────────────────────────────────────────────────────────────────
// 1. In Firebase Console → Project Settings → Service accounts → Generate
//    new private key. Download the JSON file.
//
// 2. Set the service account JSON as a Supabase secret:
//    supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='{
//      "type": "service_account",
//      "project_id": "push--notification-f5746",
//      ...
//    }'
//
// 3. Deploy:
//    supabase functions deploy exam-reminder
// ──────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { GoogleAuth } from "npm:google-auth-library@^9.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Auth helpers (same approach as send-notice-notification) ─────────────────
let _cachedToken: string | null = null;
let _tokenExpiry = 0;

async function getFcmAccessToken(): Promise<string> {
  if (_cachedToken && Date.now() < _tokenExpiry - 300_000) {
    return _cachedToken;
  }

  const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")
    ?? Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!serviceAccountJson) {
    throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON / FIREBASE_SERVICE_ACCOUNT environment variable not set");
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
                priority: "high",
                ttl: "86400s",
                notification: {
                  channel_id: "reminder_channel",
                  sound: "default",
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                  notification_priority: "PRIORITY_HIGH",
                  default_sound: true,
                  default_vibrate_timings: true,
                  default_light_settings: true,
                },
              },
              data: {
                type: "exam",
              },
            },
          }),
        },
      );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `FCM v1 API error for token ${deviceToken.substring(0, 20)}...: ${response.status} ${errorText}`,
      );
      if (response.status === 404 || response.status === 410) {
        staleTokens.push(deviceToken);
        console.warn(`Stale token queued for cleanup: ${deviceToken.substring(0, 20)}...`);
      }
      return false;
    }

    return true;
  } catch (err) {
    console.error(`FCM request error for token ${deviceToken.substring(0, 20)}...: ${err}`);
    return false;
  }
}

// ── Cron: runs daily at 8:00 AM ─────────────────────────────────────────────
Deno.cron("Exam Reminder", "0 8 * * *", async () => {
  console.log("[Cron] Exam reminder triggered at", new Date().toISOString());
  const result = await sendExamReminders();
  const body = await result.json();
  console.log(`[Cron] Exam reminder complete: ${JSON.stringify(body)}`);
});

// ── Core logic ──────────────────────────────────────────────────────────────
async function sendExamReminders(): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !supabaseServiceKey) {
    console.error("Missing Supabase environment variables");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // Get tomorrow's date
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowDate = tomorrow.toISOString().split("T")[0];

  // Find tomorrow's exams
  const { data: exams, error } = await supabase
    .from("exams")
    .select("*")
    .eq("exam_date", tomorrowDate)
    .order("start_time");

  if (error) {
    console.error("Error fetching exams:", error.message);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!exams || exams.length === 0) {
    console.log("No exams tomorrow");
    return new Response(
      JSON.stringify({ sent: 0, exams_found: 0, message: "No exams tomorrow" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Get device tokens (consistent with send-notice-notification)
  const { data: tokens, error: tokenError } = await supabase
    .from("device_tokens")
    .select("device_token");

  if (tokenError) {
    console.error("Error fetching device tokens:", tokenError.message);
    return new Response(
      JSON.stringify({ error: tokenError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!tokens || tokens.length === 0) {
    console.log("No device tokens registered");
    return new Response(
      JSON.stringify({ sent: 0, exams_found: exams.length, message: "No tokens" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Check service account config
  const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")
    ?? Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!serviceAccountJson) {
    console.error("Firebase service account not configured");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  let projectId: string;
  try {
    projectId = JSON.parse(serviceAccountJson).project_id;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid service account JSON" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  // Send notifications for each exam
  let totalSent = 0;
  let totalFailed = 0;
  const staleTokens: string[] = [];

  for (const exam of exams) {
    const startTime = exam.start_time ? exam.start_time.substring(0, 5) : "TBD";
    const room = exam.room ?? "";
    const examType = exam.exam_type ?? "Exam";
    const subject = exam.subject ?? "Unknown";

    const title = `📝 Exam Tomorrow: ${subject}`;
    const body = room
      ? `${examType} — ${subject} at ${startTime} in Room ${room}`
      : `${examType} — ${subject} at ${startTime}`;

    for (const tokenData of tokens as { device_token: string }[]) {
      const token = tokenData.device_token;
      if (!token) continue;

      const ok = await sendFcmV1(token, title, body, projectId, staleTokens);
      if (ok) totalSent++;
      else totalFailed++;
    }
  }

  // Clean up stale/invalid tokens from the database
  let removedStale = 0;
  if (staleTokens.length > 0) {
    const { error: deleteError, count } = await supabase
      .from("device_tokens")
      .delete()
      .in("device_token", staleTokens);
    if (deleteError) {
      console.error("Error cleaning up stale tokens:", deleteError.message);
    } else {
      removedStale = count ?? staleTokens.length;
      console.log(`Cleaned up ${removedStale} stale token(s) from device_tokens`);
    }
  }

  console.log(
    `Exam reminders: ${totalSent} sent, ${totalFailed} failed, ${removedStale} stale tokens removed for ${exams.length} exam(s)`,
  );

  return new Response(
    JSON.stringify({
      success: true,
      exams_found: exams.length,
      sent: totalSent,
      failed: totalFailed,
      stale_removed: removedStale,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

// ── HTTP handler (for manual invocation / testing) ──────────────────────────
serve(async () => {
  return await sendExamReminders();
});
