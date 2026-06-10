import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireString, requireUUID, handleValidationError } from '../_shared/validate.ts';

serve(async (req) => {
  try {
    let action: string;
    let booking_id: string;
    try {
      const body = await req.json().catch(() => ({}));
      action = requireString(body.action, 'action');
      booking_id = requireUUID(body.booking_id, 'booking_id');
    } catch (err) {
      return handleValidationError(err);
    }
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
    console.error('[widget-action]', e);
    return new Response(JSON.stringify({ error: 'Internal server error' }), { status: 500 });
  }
});
