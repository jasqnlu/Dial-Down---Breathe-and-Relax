import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  AppleRevokeError,
  makeAppleClientSecret,
  revokeAppleAuthorization,
  type AppleConfig,
} from "./apple.ts";

// A throwaway P-256 key per test run, exported as the same PKCS#8 PEM
// shape Apple's downloadable .p8 file uses.
async function testConfig(): Promise<{ cfg: AppleConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...pkcs8));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;
  return {
    cfg: { teamID: "TEAM123456", keyID: "KEY1234567", clientID: "com.example.app", privateKeyPEM: pem },
    publicKey: pair.publicKey,
  };
}

function b64urlDecode(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

Deno.test("client secret carries Apple's required header and claims", async () => {
  const { cfg } = await testConfig();
  const now = new Date("2026-10-01T00:00:00Z");
  const jwt = await makeAppleClientSecret(cfg, now);
  const [h, p] = jwt.split(".");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  assertEquals(header, { alg: "ES256", kid: "KEY1234567" });
  assertEquals(claims.iss, "TEAM123456");
  assertEquals(claims.sub, "com.example.app");
  assertEquals(claims.aud, "https://appleid.apple.com");
  assertEquals(claims.iat, Math.floor(now.getTime() / 1000));
  assertEquals(claims.exp, claims.iat + 300);
});

Deno.test("client secret signature verifies with the matching public key", async () => {
  const { cfg, publicKey } = await testConfig();
  const jwt = await makeAppleClientSecret(cfg);
  const [h, p, s] = jwt.split(".");
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, publicKey,
    b64urlDecode(s) as BufferSource, new TextEncoder().encode(`${h}.${p}`),
  );
  assertEquals(ok, true);
});

Deno.test("revoke exchanges the code, then revokes the refresh token", async () => {
  const { cfg } = await testConfig();
  const calls: { url: string; form: URLSearchParams }[] = [];
  const fakeFetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url, form: new URLSearchParams(init!.body as string) });
    if (url.endsWith("/auth/token")) {
      return new Response(JSON.stringify({ refresh_token: "rt-1" }), { status: 200 });
    }
    return new Response("", { status: 200 });
  }) as typeof fetch;

  await revokeAppleAuthorization("code-1", cfg, fakeFetch);

  assertEquals(calls.map((c) => c.url), [
    "https://appleid.apple.com/auth/token",
    "https://appleid.apple.com/auth/revoke",
  ]);
  assertEquals(calls[0].form.get("grant_type"), "authorization_code");
  assertEquals(calls[0].form.get("code"), "code-1");
  assertEquals(calls[0].form.get("client_id"), "com.example.app");
  assertEquals(calls[1].form.get("token"), "rt-1");
  assertEquals(calls[1].form.get("token_type_hint"), "refresh_token");
  assertEquals(calls[1].form.get("client_id"), "com.example.app");
});

Deno.test("a rejected code exchange throws at the token step and never revokes", async () => {
  const { cfg } = await testConfig();
  let revokeCalled = false;
  const fakeFetch = (async (url: string) => {
    if (url.endsWith("/auth/revoke")) revokeCalled = true;
    return new Response('{"error":"invalid_grant"}', { status: 400 });
  }) as typeof fetch;

  const err = await assertRejects(
    () => revokeAppleAuthorization("stale", cfg, fakeFetch), AppleRevokeError,
  );
  assertEquals(err.step, "token");
  assertEquals(err.status, 400);
  assertEquals(revokeCalled, false);
});

Deno.test("a token response without refresh_token throws", async () => {
  const { cfg } = await testConfig();
  const fakeFetch = (async () => new Response("{}", { status: 200 })) as typeof fetch;
  await assertRejects(() => revokeAppleAuthorization("c", cfg, fakeFetch), AppleRevokeError);
});

Deno.test("a failed revoke call throws at the revoke step", async () => {
  const { cfg } = await testConfig();
  const fakeFetch = (async (url: string) =>
    url.endsWith("/auth/token")
      ? new Response(JSON.stringify({ refresh_token: "rt" }), { status: 200 })
      : new Response("nope", { status: 503 })) as typeof fetch;
  const err = await assertRejects(
    () => revokeAppleAuthorization("c", cfg, fakeFetch), AppleRevokeError,
  );
  assertEquals(err.step, "revoke");
  assertEquals(err.status, 503);
});
