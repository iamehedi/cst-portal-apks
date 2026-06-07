// ── Supabase Edge Function: delete-user ─────────────────────────────────────
// Deletes a rejected user from auth.users (profile cascades via FK).
// This allows the user to re-register with the same email.
// Deploy with: supabase functions deploy delete-user
//
// Called from Flutter when admin rejects a pending user.
// ──────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
  try {
    // ── Authorization: only admins can delete users ──────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Missing authorization token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Server config error" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Create a client with the user's token to verify their identity
    const userClient = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });

    // Get the caller's user info
    const { data: { user: caller }, error: authError } = await userClient.auth.getUser();
    if (authError || !caller) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if the caller is an admin
    const { data: profile, error: profileError } = await userClient
      .from("profiles")
      .select("is_admin, role")
      .eq("id", caller.id)
      .single();

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: "Could not verify admin status" }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }

    const isAdmin = profile.is_admin === true || profile.role === "admin";
    if (!isAdmin) {
      return new Response(
        JSON.stringify({ error: "Only admins can delete users" }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── Proceed with deletion ────────────────────────────────────
    const { userId } = await req.json();
    if (!userId) {
      return new Response(
        JSON.stringify({ error: "Missing userId" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Use service role client for admin operations
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    // Delete auth user — profile cascades via FK ON DELETE CASCADE
    const { error } = await adminClient.auth.admin.deleteUser(userId);

    if (error) {
      console.error(`[DELETE-USER] Error deleting ${userId}: ${error.message}`);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(`[DELETE-USER] Deleted user ${userId} by admin ${caller.id}`);
    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[DELETE-USER] Fatal: ${err}`);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
