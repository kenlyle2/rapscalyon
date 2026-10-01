import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

async function signIn(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { error } = await supabase.auth.signInWithPassword({ email: String(formData.get("email")), password: String(formData.get("password")) });
  if (error) redirect("/login?error=" + encodeURIComponent("Sign-in failed"));
  redirect("/");
}

async function signUp(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { error } = await supabase.auth.signUp({ email: String(formData.get("email")), password: String(formData.get("password")) });
  redirect(error ? "/login?error=" + encodeURIComponent("Sign-up failed") : "/login?error=" + encodeURIComponent("Check your email to confirm"));
}

export default async function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <main style={{ maxWidth: 360, margin: "10vh auto", padding: "0 16px" }}>
      <h1>Sign in</h1>
      {error && <p role="alert">{error}</p>}
      <form style={{ display: "grid", gap: 8 }}>
        <input name="email" type="email" placeholder="Email" required autoComplete="email" />
        <input name="password" type="password" placeholder="Password" required minLength={8} autoComplete="current-password" />
        <button formAction={signIn}>Sign in</button>
        <button formAction={signUp}>Create account</button>
      </form>
    </main>
  );
}
