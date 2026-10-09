import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";
import { supabaseService } from "@/lib/supabase/service";

/** WordPress hands the browser here with a single-use token_hash from Supabase's admin generate_link. */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type");
  const next = url.searchParams.get("next") ?? "/";
  const target = /^\/(?!\/)/.test(next) ? next : "/"; // local paths only, no open redirect
  const fail = () => NextResponse.redirect(new URL("/login?error=" + encodeURIComponent("Sign-in link expired. Open the app again from your account."), url.origin));
  if (!tokenHash || (type !== "signup" && type !== "magiclink")) return fail(); // signup = first-time email, magiclink = existing user
  const supabase = await supabaseServer();
  const { data, error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
  if (error || !data.user) return fail();
  await supabaseService().rpc("wf_record_handoff", { p_profile: data.user.id });
  return NextResponse.redirect(new URL(target, url.origin));
}
