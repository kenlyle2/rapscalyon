import { timingSafeEqual } from "node:crypto";

/** Cron routes declared in pack.toml [cron] call this first. Constant-time bearer check against CRON_SECRET. */
export function cronAuthorized(req: Request): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const given = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  const a = Buffer.from(given), b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}
