// Run: node --test tests/ingest.test.ts   (Node 22.18+ strips types; no install needed)
import { test } from "node:test";
import assert from "node:assert/strict";
import { check, isGuest, objectKey, sniffImage, sourceUrlAllowed } from "../server/ingest/lib.ts";
import { sign } from "../server/ingest/r2.ts";

const hosts = ["cdn.mail.studio"];
const good = () => ({
  identifier: "ann@example.test", email: " Ann@Example.test ", response_id: "RESP_123", prompt: "airy", room_type: "living room", theme: "scandinavian",
  result_urls: ["https://cdn.mail.studio/action_generated_files/a.png"],
});

test("a valid request is normalised", () => {
  const r = check(good(), hosts);
  assert.ok(r.ok);
  if (r.ok) { assert.equal(r.value.email, "ann@example.test"); assert.equal(r.value.space, null); assert.equal(r.value.referenceUrl, null); }
});

test("guests are rejected before anything else", () => {
  for (const g of [{ ...good(), identifier: "API_GUEST:abc", email: "" }, { ...good(), identifier: "api_guest:abc" }, { ...good(), email: "" }, { ...good(), email: undefined }]) {
    const r = check(g, hosts); assert.ok(!r.ok); if (!r.ok) { assert.equal(r.code, "guest"); assert.equal(r.status, 403); }
  }
  assert.equal(isGuest("ann@example.test", "ann@example.test"), false);
});

test("bad shapes are refused", () => {
  const cases: [object, string][] = [
    [{ ...good(), email: "not-an-email" }, "invalid_email"],
    [{ ...good(), response_id: "has space" }, "invalid_response_id"],
    [{ ...good(), response_id: "x".repeat(121) }, "invalid_response_id"],
    [{ ...good(), prompt: "" }, "invalid_fields"],
    [{ ...good(), prompt: "x".repeat(2001) }, "invalid_fields"],
    [{ ...good(), space: "x".repeat(201) }, "invalid_space"],
    [{ ...good(), result_urls: [] }, "invalid_result_urls"],
    [{ ...good(), result_urls: Array(9).fill("https://cdn.mail.studio/a.png") }, "invalid_result_urls"],
    [{ ...good(), reference_url: "http://cdn.mail.studio/a.png" }, "invalid_reference_url"],
  ];
  for (const [body, code] of cases) { const r = check(body, hosts); assert.ok(!r.ok, code); if (!r.ok) assert.equal(r.code, code); }
  assert.ok(!check(null, hosts).ok); assert.ok(!check([], hosts).ok);
});

test("source URLs: https, allowed host or subdomain only, no credentials, no port, no lookalikes", () => {
  assert.ok(sourceUrlAllowed("https://cdn.mail.studio/x.png", hosts));
  assert.ok(sourceUrlAllowed("https://a.cdn.mail.studio/x.png", hosts));
  for (const u of ["http://cdn.mail.studio/x.png", "https://evil.com/x.png", "https://cdn.mail.studio.evil.com/x.png", "https://notcdn.mail.studio/x.png",
    "https://u:p@cdn.mail.studio/x.png", "https://cdn.mail.studio:8443/x.png", "https://169.254.169.254/latest", "file:///etc/passwd", "javascript:alert(1)", "", 5]) {
    assert.ok(!sourceUrlAllowed(u, hosts), String(u));
  }
});

test("images are identified by their bytes", () => {
  assert.equal(sniffImage(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]))?.ext, "png");
  assert.equal(sniffImage(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0]))?.ext, "jpg");
  assert.equal(sniffImage(new TextEncoder().encode("RIFF\0\0\0\0WEBPVP8 "))?.ext, "webp");
  assert.equal(sniffImage(new TextEncoder().encode("<html>not an image</html>")), null);
  assert.equal(sniffImage(new Uint8Array()), null);
});

test("object keys satisfy the database key check", () => {
  const k = objectKey("designs", "6f1c2d3e-0000-4000-8000-000000000001", "abcdef0123456789", 2, "png");
  assert.match(k, /^[A-Za-z0-9_./-]{1,255}$/); assert.ok(!k.includes(".."));
});

// AWS's published Signature V4 example (GET Object with a Range header), so a signing bug cannot hide behind "it looks right".
test("SigV4 matches the AWS documentation example", () => {
  const s = sign({ method: "GET", host: "examplebucket.s3.amazonaws.com", path: "/test.txt", headers: { range: "bytes=0-9" },
    payloadHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", region: "us-east-1", service: "s3",
    accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", amzDate: "20130524T000000Z" });
  assert.equal(s.signedHeaders, "host;range;x-amz-content-sha256;x-amz-date");
  assert.equal(s.signature, "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41");
});
