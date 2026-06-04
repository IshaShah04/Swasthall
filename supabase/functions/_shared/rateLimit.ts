// supabase/functions/_shared/rateLimit.ts
// Shared atomic rate limiter backed by public.bump_fn_rate_limit().
// Run the SQL patch that creates bump_fn_rate_limit before deploying functions that import this file.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  fnName: string,
  maxCalls: number,
  windowSeconds = 60,
): Promise<{ allowed: boolean; remaining: number }> {
  const { data, error } = await supabase.rpc("bump_fn_rate_limit", {
    p_user_id: userId,
    p_fn_name: fnName,
    p_max_calls: maxCalls,
    p_window_seconds: windowSeconds,
  });

  if (error) {
    console.error("Rate limit RPC error:", error.message);
    // Fail closed for payment/call/AI functions. If this blocks during deploy,
    // run the SQL patch that creates public.bump_fn_rate_limit().
    return { allowed: false, remaining: 0 };
  }

  const row = Array.isArray(data) ? data[0] : data;
  return {
    allowed: Boolean(row?.allowed),
    remaining: Number(row?.remaining ?? 0),
  };
}
