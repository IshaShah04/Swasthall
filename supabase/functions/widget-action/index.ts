import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { action, booking_id } = await req.json();
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response("Unauthorized", { status: 401 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    if (action === "mark_booking_completed") {
      const { error } = await supabase.rpc("mark_booking_completed", { p_booking_id: booking_id });
      if (error) throw error;
    } else if (action === "mark_booking_missed") {
      const { error } = await supabase.rpc("mark_booking_missed", { p_booking_id: booking_id });
      if (error) throw error;
    } else {
      return new Response("Unknown action", { status: 400 });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500 });
  }
});
