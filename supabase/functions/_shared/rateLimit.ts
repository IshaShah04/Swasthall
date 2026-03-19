// supabase/functions/_shared/rateLimit.ts
// Shared rate-limiter using a Supabase table.
// Run the SQL in sql/01_rate_limit_table.sql first.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const WINDOW_SECONDS = 60;

export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  fnName: string,
  maxCalls: number
): Promise<{ allowed: boolean; remaining: number }> {
  const windowStart = new Date(Date.now() - WINDOW_SECONDS * 1000).toISOString();

  // Count calls in the current window
  const { count, error } = await supabase
    .from("fn_rate_limits")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("fn_name", fnName)
    .gte("called_at", windowStart);

  if (error) {
    // On DB error, fail open (allow the call) but log
    console.error("Rate limit check error:", error.message);
    return { allowed: true, remaining: maxCalls };
  }

  const used = count ?? 0;

  if (used >= maxCalls) {
    return { allowed: false, remaining: 0 };
  }

  // Record this call
  await supabase.from("fn_rate_limits").insert({
    user_id: userId,
    fn_name: fnName,
    called_at: new Date().toISOString(),
  });

  return { allowed: true, remaining: maxCalls - used - 1 };
}
