// Minimal Cloudflare R2 (S3 API) uploader with AWS Signature V4. No dependencies; imports nothing relative so tests can load it.
import { createHash, createHmac } from "node:crypto";

const hex = (d: string | Uint8Array) => createHash("sha256").update(d).digest("hex");
const hmac = (k: string | Buffer, d: string) => createHmac("sha256", k).update(d).digest();
const enc = (s: string) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());

export type SignInput = {
  method: string; host: string; path: string; headers: Record<string, string>; payloadHash: string;
  region: string; service: string; accessKey: string; secretKey: string; amzDate: string; // 20130524T000000Z
};

/** Signs a request with no query string. `headers` are the extra signed headers (lowercase names); host, x-amz-date and the payload hash are added. */
export function sign(i: SignInput): { authorization: string; signature: string; signedHeaders: string } {
  const day = i.amzDate.slice(0, 8);
  const all: Record<string, string> = { ...i.headers, host: i.host, "x-amz-content-sha256": i.payloadHash, "x-amz-date": i.amzDate };
  const names = Object.keys(all).sort();
  const canonicalHeaders = names.map((n) => `${n}:${all[n].trim().replace(/\s+/g, " ")}\n`).join("");
  const signedHeaders = names.join(";");
  const canonicalPath = i.path.split("/").map(enc).join("/");
  const canonical = [i.method, canonicalPath, "", canonicalHeaders, signedHeaders, i.payloadHash].join("\n");
  const scope = `${day}/${i.region}/${i.service}/aws4_request`;
  const toSign = ["AWS4-HMAC-SHA256", i.amzDate, scope, hex(canonical)].join("\n");
  const key = hmac(hmac(hmac(hmac("AWS4" + i.secretKey, day), i.region), i.service), "aws4_request");
  const signature = createHmac("sha256", key).update(toSign).digest("hex");
  return { signature, signedHeaders, authorization: `AWS4-HMAC-SHA256 Credential=${i.accessKey}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}` };
}

export type R2Config = { accountId: string; accessKeyId: string; secretAccessKey: string; bucket: string };

export function r2FromEnv(env: Record<string, string | undefined> = process.env): R2Config | null {
  const { R2_ACCOUNT_ID: accountId, R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey, R2_BUCKET: bucket } = env;
  return accountId && accessKeyId && secretAccessKey && bucket ? { accountId, accessKeyId, secretAccessKey, bucket } : null;
}

/** PUT an object. Overwrites, so a retry with the same key is harmless. Throws on any non-2xx. */
export async function putObject(c: R2Config, key: string, body: Uint8Array, contentType: string): Promise<void> {
  const host = `${c.accountId}.r2.cloudflarestorage.com`;
  const path = `/${c.bucket}/${key}`;
  const amzDate = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const s = sign({ method: "PUT", host, path, headers: { "content-type": contentType }, payloadHash: hex(body), region: "auto", service: "s3",
    accessKey: c.accessKeyId, secretKey: c.secretAccessKey, amzDate });
  const res = await fetch(`https://${host}${path.split("/").map(enc).join("/")}`, {
    method: "PUT", body: body as BodyInit,
    headers: { "content-type": contentType, "x-amz-content-sha256": hex(body), "x-amz-date": amzDate, authorization: s.authorization },
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`r2 put failed: HTTP ${res.status}`);
}
