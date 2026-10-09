import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { packRegistry } from "@/lib/packs/registry.generated";

async function signIn(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { error } = await supabase.auth.signInWithPassword({ email: String(formData.get("email")), password: String(formData.get("password")) });
  if (error) redirect("/login?error=" + encodeURIComponent("Sign-in failed"));
  redirect("/");
}

async function signUp(formData: FormData) {
  "use server";
  if (!packRegistry.auth.signup) redirect("/login?error=" + encodeURIComponent("Sign-up is not available here"));
  const supabase = await supabaseServer();
  const { error } = await supabase.auth.signUp({ email: String(formData.get("email")), password: String(formData.get("password")) });
  redirect(error ? "/login?error=" + encodeURIComponent("Sign-up failed") : "/login?error=" + encodeURIComponent("Check your email to confirm"));
}

export default async function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const { login_path, login_env } = packRegistry.auth;
  const external = login_env ? process.env[login_env] : undefined; // an installed account-mode pack owns sign-in
  const target = login_path ?? external;
  if (target && /^(\/(?!\/)|https:\/\/)/.test(target)) redirect(target);
  if (login_env && !target) return <main style={{ maxWidth: 360, margin: "10vh auto", padding: "0 16px" }}><p role="alert">Sign-in is not configured: set {login_env}.</p></main>;
  return (
    <main style={{ maxWidth: 360, margin: "10vh auto", padding: "0 16px" }}>
      <h1>Sign in</h1>
      {error && <p role="alert">{error}</p>}
      <form style={{ display: "grid", gap: 8 }}>
        <input name="email" type="email" placeholder="Email" required autoComplete="email" />
        <input name="password" type="password" placeholder="Password" required minLength={8} autoComplete="current-password" />
        <button formAction={signIn}>Sign in</button>
        {packRegistry.auth.signup && <button formAction={signUp}>Create account</button>}
      </form>
    </main>
  );
}
