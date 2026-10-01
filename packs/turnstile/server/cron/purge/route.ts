import { cronAuthorized } from "@/lib/cron";
import { supabaseService } from "@/lib/supabase/service";

async function purge(req: Request) {
  if (!cronAuthorized(req)) return new Response("unauthorized", { status: 401 });
  const { data, error } = await supabaseService().rpc("ts_purge_old", { p_days: 30 });
  return error ? new Response("failed", { status: 500 }) : Response.json({ purged: data });
}
export const GET = purge, POST = purge;
