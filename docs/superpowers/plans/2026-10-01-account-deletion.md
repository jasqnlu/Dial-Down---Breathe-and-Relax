# Full Account Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Delete Account" fully delete the user's account and data: Sign in with Apple is revoked, every row the user owns and their Supabase user record are removed on the server, and the phone is returned to a fresh-install state. Nothing is deleted anywhere unless the server confirms.

**Architecture:** A new Supabase Edge Function `delete-account` holds the service-role key and does the server work in a fixed order: verify the caller → revoke Apple (Apple users only) → delete owned rows → delete the auth user. The app calls it through `SupabaseService.deleteAccount(appleAuthorizationCode:)`. `AuthManager.deleteAccount(appleReauth:)` orchestrates it and clears auth state only after success. `LocalDataEraser` then wipes local data. Apple users re-confirm through a programmatic Sign in with Apple sheet (`AppleReauthenticator`), which yields the one-time code Apple's revoke flow needs.

**Tech Stack:** Supabase Edge Functions (Deno 2, TypeScript, `@supabase/supabase-js@2` via esm.sh, Web Crypto for ES256), Swift/SwiftUI, SwiftData, AuthenticationServices, Swift Testing.

**Spec:** No separate spec document. The decisions below were agreed in conversation on 2026-10-01, and this section is the spec.

### Decisions (the spec)

1. **Apple revocation:** at delete time an Apple user re-confirms with Sign in with Apple. The fresh `authorizationCode` goes to the server, which exchanges it at `https://appleid.apple.com/auth/token` and revokes the resulting refresh token at `https://appleid.apple.com/auth/revoke`. No Apple tokens are ever stored.
2. **Failure policy:** if the server call fails for any reason (offline, Apple error, server error), show an error, keep the user signed in, and delete nothing locally. The user can retry.
3. **Local data:** on success, wipe the phone back to a fresh-install state: all user SwiftData rows, app UserDefaults, the profile photo, and pending local notifications. Keep only the bundled seed exercise catalog and its two version counters, which are content rather than user data.

## Global Constraints

- Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Module: `@testable import BreathRelaxStretch`. Files in `Breath - Relax & StretchTests/` are auto-included in the target (folder sync), so there's no project-file editing.
- Unit-test command (run from the repo root):
  `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests/<SuiteName>"`
- The app target defaults declarations to `@MainActor`. New types used from the `SupabaseService` actor must be `nonisolated`. DTOs (Codable request/response bodies) live in `Services/SupabaseDTOs.swift`, never in `SupabaseService.swift`.
- No third-party Swift dependencies; Supabase is spoken over raw `URLSession`.
- Edge Function secrets are read with `Deno.env.get`, are **never committed**, and a missing secret fails closed (nothing gets deleted).
- Apple Team ID is `F4NF2ZRZS9`. Apple `client_id` for a native app is the bundle ID `com.jasonlu.Dial--Down--Breath--Stretch`.
- Every new user-facing string is in English, using `LocalizedStringKey` literals in SwiftUI so it lands in `Localizable.xcstrings`.
- Commit with `git add <files>` and then a plain `git commit -m` (never `git commit -- <paths>`). End commit messages with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- After Swift code changes, run `graphify update .` from the repo root.
- Work on a branch, `feature/account-deletion`, never on `main`.

## Review Focus

1. **Partial failure on the server.** If Apple is revoked but a row or auth-user delete then fails, the response must be non-2xx, the auth user must still exist, and a retry (with a fresh Apple code) must succeed. Pinned in Task 2 (`rowDeleteFailureLeavesAuthUserForRetry`).
2. **Apple user whose original Supabase exchange failed** (`isBackendAuthenticated == false`, provider `.apple`). They may still have a server account, so deletion must first trade the re-auth identity token for a session and then delete. It must never silently do a local-only delete. Pinned in Task 5 (`appleUserWithoutBackendSessionExchangesFirst`).
3. **User cancels the Apple sheet.** Nothing happens: no error alert, still signed in. Pinned in Task 6 (cancellation maps to `CancellationError`, and the view ignores it). Verified manually in the simulator.
4. **Expired session.** Refresh fails, so there's no token. The app must show "session has expired", make no network call to the function, and stay signed in. Pinned in Task 3 (`deleteAccountWithoutASessionThrowsNotSignedInWithoutCallingTheNetwork`).
5. **Seed catalog survives the wipe.** Seed exercises (non-nil `seedID`) and `seedDataVersion` must survive, so the next launch neither re-seeds nor shows "New Content Added". Pinned in Task 4 (`eraseKeepsSeedCatalogAndItsVersionCounters`).

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `supabase/functions/delete-account/apple.ts` | Create | ES256 client-secret JWT + Apple code→refresh-token→revoke |
| `supabase/functions/delete-account/apple_test.ts` | Create | Deno tests for `apple.ts` |
| `supabase/functions/delete-account/handler.ts` | Create | Pure request handler with injected dependencies (ordering and status codes) |
| `supabase/functions/delete-account/handler_test.ts` | Create | Deno tests for `handler.ts` |
| `supabase/functions/delete-account/index.ts` | Create | Wires real Supabase admin client and secrets into the handler |
| `supabase/config.toml` | Modify | `[functions.delete-account] verify_jwt = true` |
| `Breath - Relax & Stretch/Services/SupabaseDTOs.swift` | Modify | `DeleteAccountBody`, `DeleteAccountErrorBody` |
| `Breath - Relax & Stretch/Services/AccountDeletionError.swift` | Create | User-facing error enum + server-code mapping |
| `Breath - Relax & Stretch/Services/SupabaseService.swift` | Modify | `deleteAccount(appleAuthorizationCode:)` + `SupabaseAccountDeleting` seam |
| `Breath - Relax & Stretch/Services/LocalDataEraser.swift` | Create | Fresh-install wipe of SwiftData/UserDefaults/photo |
| `Breath - Relax & Stretch/Services/AuthManager.swift` | Modify | `AppleReauthCredential`, async `deleteAccount(appleReauth:)`, injected deleter |
| `Breath - Relax & Stretch/Services/AppleReauthenticator.swift` | Create | Programmatic Sign in with Apple sheet → `AppleReauthCredential` |
| `Breath - Relax & Stretch/Views/Profile/ProfileAccountTab.swift` | Modify | New confirm copy, progress state, error alert, orchestration |
| `Breath - Relax & StretchTests/SupabaseServiceTests.swift` | Modify | Delete-account HTTP tests; `FakeHTTPSession` gains a `.failure` case |
| `Breath - Relax & StretchTests/AuthManagerTests.swift` | Modify | Replace the old sync delete test with the async suite |
| `Breath - Relax & StretchTests/LocalDataEraserTests.swift` | Create | Wipe tests |
| `Breath - Relax & Stretch/Legal/PrivacyPolicy.html` | Modify | §8 deletion wording reflects the real behaviour |

---

### Task 0: Branch and tooling

- [ ] **Step 1: Create the branch**

```bash
cd "/Users/jasonlu/Desktop/X-Code Projects/Breath - Relax & Stretch"
git switch -c feature/account-deletion
```

- [ ] **Step 2: Install Deno (needed for Edge Function unit tests)**

```bash
which deno || brew install deno
deno --version
```
Expected: `deno 2.x`.

---

### Task 1: Apple revoke helper (`apple.ts`)

**Files:**
- Create: `supabase/functions/delete-account/apple.ts`
- Test: `supabase/functions/delete-account/apple_test.ts`

**Interfaces:**
- Produces:
  - `interface AppleConfig { teamID: string; keyID: string; clientID: string; privateKeyPEM: string }`
  - `makeAppleClientSecret(cfg: AppleConfig, now?: Date): Promise<string>`
  - `revokeAppleAuthorization(code: string, cfg: AppleConfig, fetchFn?: typeof fetch, now?: Date): Promise<void>`. It throws `AppleRevokeError` on any failure.
  - `class AppleRevokeError extends Error { step: "token" | "revoke"; status: number }`

- [ ] **Step 1: Write the failing tests**

`supabase/functions/delete-account/apple_test.ts`:
```ts
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
    b64urlDecode(s), new TextEncoder().encode(`${h}.${p}`),
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd supabase/functions/delete-account && deno test apple_test.ts`
Expected: FAIL. The module `./apple.ts` isn't found.

- [ ] **Step 3: Implement `apple.ts`**

```ts
// supabase/functions/delete-account/apple.ts
//
// Sign in with Apple revocation (App Store Guideline 5.1.1(v): deleting an
// account must also revoke the app's Apple authorization). Apple only
// revokes a refresh or access token, and Supabase never stores Apple's
// tokens, so the app sends a fresh one-time authorization code from a
// re-confirm sheet. That code is exchanged here for a refresh token, which
// is revoked immediately. Nothing is persisted.
//
// The ES256 client secret is built with Web Crypto, the same approach as
// send-streak-warnings' APNs JWT: WebCrypto's raw r||s ECDSA output is
// already the JOSE signature format.

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export interface AppleConfig {
  teamID: string;
  keyID: string;
  /** The app's bundle ID. Native Sign in with Apple uses it as client_id. */
  clientID: string;
  /** Contents of the Sign in with Apple .p8 key file. */
  privateKeyPEM: string;
}

export class AppleRevokeError extends Error {
  constructor(
    readonly step: "token" | "revoke",
    readonly status: number,
    detail: string,
  ) {
    super(`Apple ${step} request failed (${status}): ${detail}`);
    this.name = "AppleRevokeError";
  }
}

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const b of buf) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJSON(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function importP8(pem: string): Promise<CryptoKey> {
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(stripped), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
}

/** Short-lived (5 min) client secret. It only has to outlive one request pair. */
export async function makeAppleClientSecret(
  cfg: AppleConfig,
  now: Date = new Date(),
): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  const signingInput = `${base64urlJSON({ alg: "ES256", kid: cfg.keyID })}.${
    base64urlJSON({
      iss: cfg.teamID,
      iat,
      exp: iat + 300,
      aud: "https://appleid.apple.com",
      sub: cfg.clientID,
    })
  }`;
  const key = await importP8(cfg.privateKeyPEM);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(sig)}`;
}

function form(params: Record<string, string>): RequestInit {
  return {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString(),
  };
}

/** Exchanges a one-time authorization code and revokes the resulting refresh token. */
export async function revokeAppleAuthorization(
  code: string,
  cfg: AppleConfig,
  fetchFn: typeof fetch = fetch,
  now: Date = new Date(),
): Promise<void> {
  const clientSecret = await makeAppleClientSecret(cfg, now);

  const tokenRes = await fetchFn(APPLE_TOKEN_URL, form({
    client_id: cfg.clientID,
    client_secret: clientSecret,
    code,
    grant_type: "authorization_code",
  }));
  if (!tokenRes.ok) {
    throw new AppleRevokeError("token", tokenRes.status, await tokenRes.text());
  }
  const { refresh_token } = await tokenRes.json() as { refresh_token?: string };
  if (!refresh_token) {
    throw new AppleRevokeError("token", tokenRes.status, "response had no refresh_token");
  }

  const revokeRes = await fetchFn(APPLE_REVOKE_URL, form({
    client_id: cfg.clientID,
    client_secret: clientSecret,
    token: refresh_token,
    token_type_hint: "refresh_token",
  }));
  if (!revokeRes.ok) {
    throw new AppleRevokeError("revoke", revokeRes.status, await revokeRes.text());
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd supabase/functions/delete-account && deno test apple_test.ts`
Expected: `ok | 6 passed | 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/delete-account/apple.ts supabase/functions/delete-account/apple_test.ts
git commit -m "feat(server): Sign in with Apple revoke helper for account deletion

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `delete-account` handler, wiring and config

**Files:**
- Create: `supabase/functions/delete-account/handler.ts`
- Create: `supabase/functions/delete-account/index.ts`
- Modify: `supabase/config.toml` (append after the `[functions.send-streak-warnings]` block)
- Test: `supabase/functions/delete-account/handler_test.ts`

**Interfaces:**
- Consumes: `revokeAppleAuthorization`, `AppleConfig` (Task 1).
- Produces the HTTP contract the app depends on (Task 3):
  - `POST /functions/v1/delete-account` with header `Authorization: Bearer <user access token>` and body `{"apple_authorization_code"?: string}`.
  - `200 {"deleted":true}`
  - `400 {"error":"apple_reauth_required"}`. The account's providers include `apple` but there's no code.
  - `401 {"error":"unauthorized"}`. The token is missing, invalid or expired.
  - `405 {"error":"method_not_allowed"}`
  - `500 {"error":"delete_failed"}`
  - `502 {"error":"apple_revoke_failed"}`

- [ ] **Step 1: Write the failing tests**

`supabase/functions/delete-account/handler_test.ts`:
```ts
import { assertEquals } from "jsr:@std/assert@1";
import { type DeleteAccountDeps, handleDeleteAccount } from "./handler.ts";

type User = { id: string; providers: string[] };

function fakeDeps(user: User | null, overrides: Partial<DeleteAccountDeps> = {}) {
  const log: string[] = [];
  const deps: DeleteAccountDeps = {
    getUser: async (jwt) => { log.push(`getUser:${jwt}`); return user; },
    revokeApple: async (code) => { log.push(`revokeApple:${code}`); },
    deleteUserRows: async (id) => { log.push(`deleteUserRows:${id}`); },
    deleteAuthUser: async (id) => { log.push(`deleteAuthUser:${id}`); },
    ...overrides,
  };
  return { deps, log };
}

function post(body?: unknown, token: string | null = "user-jwt"): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("http://localhost/delete-account", {
    method: "POST", headers, body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function status(res: Response): Promise<[number, unknown]> {
  return [res.status, await res.json()];
}

Deno.test("non-POST is rejected", async () => {
  const { deps } = fakeDeps({ id: "u1", providers: ["email"] });
  const res = await handleDeleteAccount(new Request("http://x", { method: "GET" }), deps);
  assertEquals(await status(res), [405, { error: "method_not_allowed" }]);
});

Deno.test("missing bearer token is unauthorized and touches nothing", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email"] });
  const res = await handleDeleteAccount(post({}, null), deps);
  assertEquals(await status(res), [401, { error: "unauthorized" }]);
  assertEquals(log, []);
});

Deno.test("a token that resolves to no user is unauthorized", async () => {
  const { deps, log } = fakeDeps(null);
  const res = await handleDeleteAccount(post({}), deps);
  assertEquals(await status(res), [401, { error: "unauthorized" }]);
  assertEquals(log, ["getUser:user-jwt"]);
});

Deno.test("email user: rows then auth user, no Apple call", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email"] });
  const res = await handleDeleteAccount(post(), deps); // empty body is fine
  assertEquals(await status(res), [200, { deleted: true }]);
  assertEquals(log, ["getUser:user-jwt", "deleteUserRows:u1", "deleteAuthUser:u1"]);
});

Deno.test("apple user without a code is told to re-authenticate; nothing deleted", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["apple"] });
  const res = await handleDeleteAccount(post({}), deps);
  assertEquals(await status(res), [400, { error: "apple_reauth_required" }]);
  assertEquals(log, ["getUser:user-jwt"]);
});

Deno.test("apple user: revoke happens BEFORE any deletion", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email", "apple"] });
  const res = await handleDeleteAccount(post({ apple_authorization_code: "c1" }), deps);
  assertEquals(await status(res), [200, { deleted: true }]);
  assertEquals(log, [
    "getUser:user-jwt", "revokeApple:c1", "deleteUserRows:u1", "deleteAuthUser:u1",
  ]);
});

Deno.test("apple revoke failure is a 502 and nothing is deleted", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["apple"] }, {
    revokeApple: async () => { throw new Error("apple down"); },
  });
  const res = await handleDeleteAccount(post({ apple_authorization_code: "c1" }), deps);
  assertEquals(await status(res), [502, { error: "apple_revoke_failed" }]);
  assertEquals(log, ["getUser:user-jwt"]);
});

Deno.test("rowDeleteFailureLeavesAuthUserForRetry", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email"] }, {
    deleteUserRows: async () => { throw new Error("db down"); },
  });
  const res = await handleDeleteAccount(post(), deps);
  assertEquals(await status(res), [500, { error: "delete_failed" }]);
  assertEquals(log.includes("deleteAuthUser:u1"), false);
});

Deno.test("auth user delete failure is a 500", async () => {
  const { deps } = fakeDeps({ id: "u1", providers: ["email"] }, {
    deleteAuthUser: async () => { throw new Error("admin api down"); },
  });
  const res = await handleDeleteAccount(post(), deps);
  assertEquals(await status(res), [500, { error: "delete_failed" }]);
});

Deno.test("a blank or non-string code counts as no code", async () => {
  const { deps } = fakeDeps({ id: "u1", providers: ["apple"] });
  for (const body of [{ apple_authorization_code: "" }, { apple_authorization_code: 42 }]) {
    const res = await handleDeleteAccount(post(body), deps);
    assertEquals(await status(res), [400, { error: "apple_reauth_required" }]);
  }
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd supabase/functions/delete-account && deno test handler_test.ts`
Expected: FAIL. The module `./handler.ts` isn't found.

- [ ] **Step 3: Implement `handler.ts`**

```ts
// supabase/functions/delete-account/handler.ts
//
// Called by the app's Delete Account button with the user's own session
// token. All side effects are injected (see index.ts), so the ordering
// guarantees below are unit-tested:
//
//   1. Resolve the caller from their token. Never trust a user id from the body.
//   2. Apple accounts: revoke Sign in with Apple FIRST. If Apple fails,
//      nothing has been deleted and the user can simply retry. (The other
//      order could leave a deleted account with a live Apple authorization
//      that nothing can ever revoke.)
//   3. Delete every row the user owns, then the auth user. If the rows
//      fail, the auth user is kept so a retry can still authenticate.

export interface DeleteAccountDeps {
  /** null when the token is missing/invalid/expired. */
  getUser(jwt: string): Promise<{ id: string; providers: string[] } | null>;
  revokeApple(authorizationCode: string): Promise<void>;
  deleteUserRows(userID: string): Promise<void>;
  deleteAuthUser(userID: string): Promise<void>;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleDeleteAccount(
  req: Request,
  deps: DeleteAccountDeps,
): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const header = req.headers.get("Authorization") ?? "";
  const jwt = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!jwt) return json(401, { error: "unauthorized" });

  const user = await deps.getUser(jwt);
  if (!user) return json(401, { error: "unauthorized" });

  let code: string | undefined;
  try {
    const body = await req.json();
    const raw = body?.apple_authorization_code;
    if (typeof raw === "string" && raw.length > 0) code = raw;
  } catch {
    // Empty or non-JSON body: fine for non-Apple accounts.
  }

  if (user.providers.includes("apple")) {
    if (!code) return json(400, { error: "apple_reauth_required" });
    try {
      await deps.revokeApple(code);
    } catch (e) {
      console.error("apple revoke failed:", e);
      return json(502, { error: "apple_revoke_failed" });
    }
  }

  try {
    await deps.deleteUserRows(user.id);
    await deps.deleteAuthUser(user.id);
  } catch (e) {
    console.error("account delete failed:", e);
    return json(500, { error: "delete_failed" });
  }

  return json(200, { deleted: true });
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd supabase/functions/delete-account && deno test handler_test.ts`
Expected: `ok | 10 passed | 0 failed`.

- [ ] **Step 5: Implement `index.ts` (wiring only; the logic is tested above)**

```ts
// supabase/functions/delete-account/index.ts
//
// Production wiring for handler.ts. Secrets (set with `supabase secrets set`,
// never committed):
//   APPLE_TEAM_ID        F4NF2ZRZS9
//   APPLE_CLIENT_ID      com.jasonlu.Dial--Down--Breath--Stretch
//   APPLE_SIWA_KEY_ID    Key ID of the Sign in with Apple key (NOT the APNs key)
//   APPLE_SIWA_KEY_P8    full contents of that .p8 file
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// A missing Apple secret makes revokeApple throw, so Apple users get a 502
// and nothing is deleted (fail closed).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleDeleteAccount } from "./handler.ts";
import { revokeAppleAuthorization } from "./apple.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// [table, owner column]. None of these has a foreign key to auth.users
// (see supabase_schema.sql), so deleting the auth user would NOT cascade.
// Each one is removed explicitly. push_tokens goes first so the streak cron
// can't push to an account that's halfway through deletion.
const OWNED_ROWS: ReadonlyArray<readonly [string, string]> = [
  ["push_tokens", "user_id"],
  ["leaderboard", "user_id"],
  ["sessions", "user_id"],
  ["routines", "author_id"],
  ["profiles", "id"],
];

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} not configured`);
  return value;
}

Deno.serve((req) =>
  handleDeleteAccount(req, {
    async getUser(jwt) {
      const { data, error } = await admin.auth.getUser(jwt);
      if (error || !data.user) return null;
      const meta = data.user.app_metadata ?? {};
      const providers: string[] = Array.isArray(meta.providers)
        ? meta.providers
        : typeof meta.provider === "string" ? [meta.provider] : [];
      return { id: data.user.id, providers };
    },
    async revokeApple(code) {
      await revokeAppleAuthorization(code, {
        teamID: requiredEnv("APPLE_TEAM_ID"),
        keyID: requiredEnv("APPLE_SIWA_KEY_ID"),
        clientID: requiredEnv("APPLE_CLIENT_ID"),
        privateKeyPEM: requiredEnv("APPLE_SIWA_KEY_P8"),
      });
    },
    async deleteUserRows(userID) {
      for (const [table, column] of OWNED_ROWS) {
        const { error } = await admin.from(table).delete().eq(column, userID);
        if (error) throw new Error(`${table}: ${error.message}`);
      }
    },
    async deleteAuthUser(userID) {
      const { error } = await admin.auth.admin.deleteUser(userID);
      if (error) throw error;
    },
  })
);
```

- [ ] **Step 6: Type-check the whole function**

Run: `cd supabase/functions/delete-account && deno check index.ts && deno test`
Expected: `deno check` prints no errors, and all 16 tests pass.

- [ ] **Step 7: Register the function in `supabase/config.toml`**

Append directly after the `[functions.send-streak-warnings]` block:
```toml

# Called by the app's Delete Account button with the user's own access
# token. verify_jwt rejects anonymous callers at the gateway; the function
# additionally resolves the user from that token and only ever deletes
# that user. See supabase/functions/delete-account/handler.ts.
[functions.delete-account]
enabled = true
verify_jwt = true
```

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/delete-account supabase/config.toml
git commit -m "feat(server): delete-account Edge Function

Revokes Sign in with Apple first, then deletes every owned row and the
auth user. Fails closed on any error so the client can retry.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: App ↔ function client (`SupabaseService.deleteAccount`)

**Files:**
- Create: `Breath - Relax & Stretch/Services/AccountDeletionError.swift`
- Modify: `Breath - Relax & Stretch/Services/SupabaseDTOs.swift` (append at the end)
- Modify: `Breath - Relax & Stretch/Services/SupabaseService.swift`. Add the method in a new `// MARK: - Account deletion` section directly before `// MARK: - HTTP helpers`, and add the protocol after the `SupabaseProfileStoring` extension near the end of the file.
- Test: `Breath - Relax & StretchTests/SupabaseServiceTests.swift`

**Interfaces:**
- Consumes: the HTTP contract from Task 2.
- Produces:
  - `nonisolated enum AccountDeletionError: LocalizedError, Equatable { case notSignedIn, appleReauthRequired, appleRevokeFailed, network, server }` plus `init(serverCode: String?, status: Int)`
  - `protocol SupabaseAccountDeleting: Sendable { func deleteAccount(appleAuthorizationCode: String?) async throws }`, which `SupabaseService` conforms to.

- [ ] **Step 1: Let `FakeHTTPSession` simulate a transport failure**

In `SupabaseServiceTests.swift`, change the `Canned` enum and the switch in `FakeHTTPSession`:
```swift
    enum Canned {
        case success(status: Int, body: Data)
        case failure(URLError)
    }
```
```swift
        switch next {
        case .success(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        case .failure(let error):
            throw error
        }
```

- [ ] **Step 2: Write the failing tests**

Append to `SupabaseServiceTests.swift` (new extension at the end of the file):
```swift
// MARK: - Account deletion

extension SupabaseServiceTests {

    @Test @MainActor func deleteAccountPostsTheCodeWithTheUserTokenAndClearsTheSession() async throws {
        let keychain = try signedInKeychain(userID: "u1")
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data(#"{"deleted":true}"#.utf8))
        ])
        let service = SupabaseService(keychain: keychain, urlSession: session)

        try await service.deleteAccount(appleAuthorizationCode: "code-1")

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/functions/v1/delete-account")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        let json = try #require(try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any])
        #expect(json["apple_authorization_code"] as? String == "code-1")
        #expect(keychain.loadCredential(account: "supabase.session") == nil)
    }

    @Test @MainActor func deleteAccountOmitsTheCodeKeyForNonAppleAccounts() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("{}".utf8))])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)

        try await service.deleteAccount(appleAuthorizationCode: nil)

        let body = try #require(session.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["apple_authorization_code"] == nil)
    }

    @Test @MainActor func deleteAccountWithoutASessionThrowsNotSignedInWithoutCallingTheNetwork() async {
        let session = FakeHTTPSession(responses: [])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)

        await #expect(throws: AccountDeletionError.notSignedIn) {
            try await service.deleteAccount(appleAuthorizationCode: nil)
        }
        #expect(session.requests.isEmpty)
    }

    @Test @MainActor func deleteAccountMapsAppleRevokeFailureAndKeepsTheSession() async throws {
        let keychain = try signedInKeychain(userID: "u1")
        let session = FakeHTTPSession(responses: [
            .success(status: 502, body: Data(#"{"error":"apple_revoke_failed"}"#.utf8))
        ])
        let service = SupabaseService(keychain: keychain, urlSession: session)

        await #expect(throws: AccountDeletionError.appleRevokeFailed) {
            try await service.deleteAccount(appleAuthorizationCode: "c")
        }
        #expect(keychain.loadCredential(account: "supabase.session") != nil)
    }

    @Test @MainActor func deleteAccountMapsServerCodesAndStatuses() async throws {
        let cases: [(Int, String, AccountDeletionError)] = [
            (400, #"{"error":"apple_reauth_required"}"#, .appleReauthRequired),
            (401, #"{"error":"unauthorized"}"#, .notSignedIn),
            (500, #"{"error":"delete_failed"}"#, .server),
            (503, "<html>gateway</html>", .server),
        ]
        for (status, body, expected) in cases {
            let session = FakeHTTPSession(responses: [.success(status: status, body: Data(body.utf8))])
            let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)
            await #expect(throws: expected) {
                try await service.deleteAccount(appleAuthorizationCode: "c")
            }
        }
    }

    @Test @MainActor func deleteAccountMapsATransportErrorToNetwork() async throws {
        let session = FakeHTTPSession(responses: [.failure(URLError(.notConnectedToInternet))])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)

        await #expect(throws: AccountDeletionError.network) {
            try await service.deleteAccount(appleAuthorizationCode: nil)
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests/SupabaseServiceTests"`
Expected: a compile failure. `deleteAccount(appleAuthorizationCode:)` and `AccountDeletionError` aren't found.

- [ ] **Step 4: Add the error type**

`Breath - Relax & Stretch/Services/AccountDeletionError.swift`:
```swift
import Foundation

/// Why Delete Account didn't go through. Every case means *nothing was
/// deleted*: the app keeps the user signed in so they can retry
/// (decision 2026-10-01). `nonisolated` because SupabaseService (an actor)
/// creates these.
nonisolated enum AccountDeletionError: LocalizedError, Equatable {
    case notSignedIn
    case appleReauthRequired
    case appleRevokeFailed
    case network
    case server

    /// Maps the delete-account Edge Function's `{"error": ...}` body, falling
    /// back to the HTTP status when the body isn't one of ours (e.g. a
    /// gateway error page).
    init(serverCode: String?, status: Int) {
        switch (serverCode, status) {
        case ("apple_reauth_required", _): self = .appleReauthRequired
        case ("apple_revoke_failed", _):   self = .appleRevokeFailed
        case (_, 401):                     self = .notSignedIn
        default:                           self = .server
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Your session has expired. Sign out, sign back in, then try deleting again.")
        case .appleReauthRequired:
            return String(localized: "Please confirm with Sign in with Apple to delete your account.")
        case .appleRevokeFailed:
            return String(localized: "Couldn't reach Apple to remove Sign in with Apple. Your account wasn't deleted. Please try again.")
        case .network:
            return String(localized: "You're offline. Your account wasn't deleted. Connect to the internet and try again.")
        case .server:
            return String(localized: "Something went wrong on our end. Your account wasn't deleted. Please try again.")
        }
    }
}
```

- [ ] **Step 5: Add the DTOs**

Append to `Breath - Relax & Stretch/Services/SupabaseDTOs.swift`:
```swift

/// Body for the delete-account Edge Function. A nil code is omitted from
/// the JSON (synthesized Encodable uses encodeIfPresent), which is what the
/// function expects for non-Apple accounts.
struct DeleteAccountBody: Encodable, Sendable {
    let appleAuthorizationCode: String?

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

/// `{"error": "<code>"}`, the delete-account function's failure body.
struct DeleteAccountErrorBody: Decodable, Sendable {
    let error: String?
}
```

- [ ] **Step 6: Add the service method**

In `SupabaseService.swift`, directly before `// MARK: - HTTP helpers`:
```swift
    // MARK: - Account deletion

    /// Calls the `delete-account` Edge Function, which revokes Sign in with
    /// Apple (when a code is given), deletes every row this user owns, then
    /// the auth user itself. On any failure it throws and leaves the local
    /// session alone so the caller can keep the user signed in to retry; on
    /// success the now-dead session is cleared.
    func deleteAccount(appleAuthorizationCode: String?) async throws {
        guard let token = await currentAccessToken() else {
            throw AccountDeletionError.notSignedIn
        }
        var request = bareRequest(path: "/functions/v1/delete-account", method: "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AccountDeletionError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.server }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(DeleteAccountErrorBody.self, from: data))?.error
            throw AccountDeletionError(serverCode: code, status: http.statusCode)
        }
        storeSession(nil)
    }
```

After `extension SupabaseService: SupabaseProfileStoring {}`:
```swift

/// Account-deletion seam so AuthManager's delete flow is testable without
/// the network.
protocol SupabaseAccountDeleting: Sendable {
    func deleteAccount(appleAuthorizationCode: String?) async throws
}

extension SupabaseService: SupabaseAccountDeleting {}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run the Step 3 command.
Expected: all `SupabaseServiceTests` pass, including the 6 new ones.

- [ ] **Step 8: Commit**

```bash
git add "Breath - Relax & Stretch/Services/AccountDeletionError.swift" "Breath - Relax & Stretch/Services/SupabaseDTOs.swift" "Breath - Relax & Stretch/Services/SupabaseService.swift" "Breath - Relax & StretchTests/SupabaseServiceTests.swift"
git commit -m "feat: SupabaseService.deleteAccount calls the delete-account function

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Local wipe (`LocalDataEraser`)

**Files:**
- Create: `Breath - Relax & Stretch/Services/LocalDataEraser.swift`
- Test: `Breath - Relax & StretchTests/LocalDataEraserTests.swift`

**Interfaces:**
- Produces: `enum LocalDataEraser { static func eraseAll(context: ModelContext, defaults: UserDefaults, domainName: String?, documentsDirectory: URL) throws }`, with production defaults `.standard`, `Bundle.main.bundleIdentifier` and the app's Documents directory.

- [ ] **Step 1: Write the failing tests**

`Breath - Relax & StretchTests/LocalDataEraserTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import BreathRelaxStretch

@MainActor
struct LocalDataEraserTests {

    private let suite = "LocalDataEraserTests.\(UUID().uuidString)"

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, FlexibilityCheckIn.self, PendingSyncOp.self,
                             Routine.self, Session.self, UserProfile.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func exercise(_ name: String, seedID: String?) -> Exercise {
        let e = Exercise(name: name, type: .stretch, targetBodyParts: [],
                         durationSeconds: 30, difficulty: 1, instructions: [])
        e.seedID = seedID
        return e
    }

    private func tempDocuments() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func eraseRemovesAllUserRowsAndCustomExercises() throws {
        let context = try makeContext()
        context.insert(Session(routineID: UUID()))
        context.insert(Routine(name: "Mine"))
        context.insert(UserProfile(profileID: "p", displayName: "Ada"))
        context.insert(FlexibilityCheckIn(test: .toeTouch, level: 1))
        context.insert(PendingSyncOp(entityType: .session, entityID: UUID(), opType: .upsert))
        context.insert(exercise("My custom stretch", seedID: nil))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: suite))
        try LocalDataEraser.eraseAll(context: context, defaults: defaults,
                                     domainName: suite, documentsDirectory: try tempDocuments())

        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Routine>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FlexibilityCheckIn>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PendingSyncOp>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test func eraseKeepsSeedCatalogAndItsVersionCounters() throws {
        let context = try makeContext()
        context.insert(exercise("Seed stretch", seedID: "seed-1"))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(7, forKey: "seedDataVersion")
        defaults.set(7, forKey: "notifiedSeedVersion")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(["neck"], forKey: "bodymap.markedRegions")
        defaults.set("Ada", forKey: "auth.displayName")

        try LocalDataEraser.eraseAll(context: context, defaults: defaults,
                                     domainName: suite, documentsDirectory: try tempDocuments())

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(defaults.integer(forKey: "seedDataVersion") == 7)
        #expect(defaults.integer(forKey: "notifiedSeedVersion") == 7)
        #expect(defaults.object(forKey: "bodymap.markedRegions") == nil)
        #expect(defaults.object(forKey: "auth.displayName") == nil)
        // Explicitly false (not just absent) so @AppStorage observers fire.
        #expect(defaults.object(forKey: "hasCompletedOnboarding") as? Bool == false)
    }

    @Test func eraseDeletesTheProfilePhotoAndToleratesItMissing() throws {
        let docs = try tempDocuments()
        let photo = docs.appendingPathComponent("profile_photo.jpg")
        try Data([0xFF]).write(to: photo)
        let defaults = try #require(UserDefaults(suiteName: suite))

        try LocalDataEraser.eraseAll(context: try makeContext(), defaults: defaults,
                                     domainName: suite, documentsDirectory: docs)
        #expect(!FileManager.default.fileExists(atPath: photo.path))

        // Second run: no photo present, so it must not throw.
        try LocalDataEraser.eraseAll(context: try makeContext(), defaults: defaults,
                                     domainName: suite, documentsDirectory: docs)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests/LocalDataEraserTests"`
Expected: a compile failure. `LocalDataEraser` isn't found.

- [ ] **Step 3: Implement**

`Breath - Relax & Stretch/Services/LocalDataEraser.swift`:
```swift
import Foundation
import SwiftData

/// Returns the device to a fresh-install state after Delete Account
/// succeeds (decision 2026-10-01: deleting the account also wipes local
/// data). Run only *after* the server confirmed, never on failure.
///
/// Keeps the bundled seed exercise catalog (content, not user data; seed
/// rows have a non-nil `seedID`) and the two counters describing which
/// catalog version is installed, so the next launch neither re-runs seed
/// migrations nor greets the user with "New Content Added".
enum LocalDataEraser {

    static let preservedDefaultsKeys = ["seedDataVersion", "notifiedSeedVersion"]
    static let profilePhotoFilename = "profile_photo.jpg" // ProfileView.profilePhotoURL

    static func eraseAll(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) throws {
        try context.delete(model: Session.self)
        try context.delete(model: Routine.self)
        try context.delete(model: UserProfile.self)
        try context.delete(model: FlexibilityCheckIn.self)
        try context.delete(model: PendingSyncOp.self)
        try context.delete(model: Exercise.self, where: #Predicate { $0.seedID == nil })
        try context.save()

        let preserved = preservedDefaultsKeys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        }
        if let domainName { defaults.removePersistentDomain(forName: domainName) }
        for (key, value) in preserved { defaults.set(value, forKey: key) }
        // An explicit write (not just the removal above) so @AppStorage
        // observers re-render and OnboardingGate routes back to onboarding.
        defaults.set(false, forKey: "hasCompletedOnboarding")

        let photo = documentsDirectory.appendingPathComponent(profilePhotoFilename)
        if FileManager.default.fileExists(atPath: photo.path) {
            try FileManager.default.removeItem(at: photo)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command.
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add "Breath - Relax & Stretch/Services/LocalDataEraser.swift" "Breath - Relax & StretchTests/LocalDataEraserTests.swift"
git commit -m "feat: LocalDataEraser wipes the device back to a fresh install

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `AuthManager.deleteAccount(appleReauth:)`

**Files:**
- Modify: `Breath - Relax & Stretch/Services/AuthManager.swift`. That's the init (around lines 180-190), the stored properties (around line 174), and the whole `// MARK: - Delete account` section (around lines 495-530).
- Test: `Breath - Relax & StretchTests/AuthManagerTests.swift`

**Interfaces:**
- Consumes: `SupabaseAccountDeleting`, `AccountDeletionError` (Task 3).
- Produces:
  - `struct AppleReauthCredential: Sendable, Equatable { let appleUserID: String; let authorizationCode: String; let identityToken: String; let rawNonce: String? }`
  - `AuthManager.init(keychain:supabase:accountDeleter:)`, where `accountDeleter` defaults to `SupabaseService.shared`
  - `func deleteAccount(appleReauth: AppleReauthCredential?) async throws`. It replaces the old synchronous `deleteAccount()`.
  - `static func randomNonce(length:)` changes from `private` to internal (still `nonisolated static`) so Task 6 can reuse it.

- [ ] **Step 1: Write the failing tests**

In `AuthManagerTests.swift`:

(a) Change `makeManager` to accept a deleter:
```swift
    private func makeManager(
        supabase: SupabaseAuthenticating = FakeSupabaseAuthenticating(),
        deleter: SupabaseAccountDeleting = FakeAccountDeleter(),
        keychain: FakeKeychainStore = FakeKeychainStore()
    ) -> AuthManager {
        AuthManager(keychain: keychain, supabase: supabase, accountDeleter: deleter)
    }
```

(b) **Delete** the old test `deleteAccountDropsTheSupabaseIdentity` (it calls the removed sync API) and add this section in its place:
```swift
    // MARK: - Delete account

    private func appleReauth() -> AppleReauthCredential {
        AppleReauthCredential(appleUserID: "apple-user-1", authorizationCode: "code-1",
                              identityToken: "id-token", rawNonce: "nonce")
    }

    /// Simulates an Apple user restored from UserDefaults: handleAppleCredential
    /// needs a real ASAuthorizationAppleIDCredential, which tests can't build.
    private func persistAppleSignIn(supabaseUserID: String?) {
        let d = UserDefaults.standard
        d.set(true, forKey: "auth.isSignedIn")
        d.set("Ada", forKey: "auth.displayName")
        d.set("apple", forKey: "auth.provider")
        if let supabaseUserID { d.set(supabaseUserID, forKey: "auth.supabaseUserID") }
    }

    @Test func deleteAccountCallsTheServerThenClearsLocalSignIn() async throws {
        let auth = FakeSupabaseAuthenticating()
        auth.signUpWithPasswordResult = .success("supabase-uid-123")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(supabase: auth, deleter: deleter)
        _ = await manager.signUp(email: "ada@example.com", password: "password123")

        try await manager.deleteAccount(appleReauth: nil)

        #expect(deleter.calls == [nil])
        #expect(!manager.isSignedIn)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func deleteAccountFailureKeepsTheUserSignedIn() async {
        let auth = FakeSupabaseAuthenticating()
        auth.signUpWithPasswordResult = .success("supabase-uid-123")
        let deleter = FakeAccountDeleter()
        deleter.result = .failure(AccountDeletionError.network)
        let manager = makeManager(supabase: auth, deleter: deleter)
        _ = await manager.signUp(email: "ada@example.com", password: "password123")

        await #expect(throws: AccountDeletionError.network) {
            try await manager.deleteAccount(appleReauth: nil)
        }
        #expect(manager.isSignedIn)
        #expect(manager.isBackendAuthenticated)
        #expect(manager.userEmail == "ada@example.com")
    }

    @Test func appleUserWithoutReauthIsRejectedBeforeAnyNetworkCall() async {
        persistAppleSignIn(supabaseUserID: "apple-uid")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter)

        await #expect(throws: AccountDeletionError.appleReauthRequired) {
            try await manager.deleteAccount(appleReauth: nil)
        }
        #expect(deleter.calls.isEmpty)
        #expect(manager.isSignedIn)
    }

    @Test func appleUserPassesTheCodeAndForgetsTheStoredAppleEmail() async throws {
        persistAppleSignIn(supabaseUserID: "apple-uid")
        let keychain = FakeKeychainStore()
        keychain.save(account: "apple-email:apple-user-1", value: "ada@privaterelay.appleid.com")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter, keychain: keychain)

        try await manager.deleteAccount(appleReauth: appleReauth())

        #expect(deleter.calls == ["code-1"])
        #expect(keychain.loadCredential(account: "apple-email:apple-user-1") == nil)
        #expect(!manager.isSignedIn)
    }

    @Test func appleUserWithoutBackendSessionExchangesFirst() async throws {
        persistAppleSignIn(supabaseUserID: nil)
        let auth = FakeSupabaseAuthenticating()
        auth.signInWithAppleResult = .success("apple-uid-late")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(supabase: auth, deleter: deleter)

        try await manager.deleteAccount(appleReauth: appleReauth())

        #expect(deleter.calls == ["code-1"])
        #expect(!manager.isSignedIn)
    }

    @Test func appleUserWhoseLateExchangeFailsIsNotDeleted() async {
        persistAppleSignIn(supabaseUserID: nil)
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter) // signInWithApple fails by default

        await #expect(throws: AccountDeletionError.server) {
            try await manager.deleteAccount(appleReauth: appleReauth())
        }
        #expect(deleter.calls.isEmpty)
        #expect(manager.isSignedIn)
    }

    @Test func localOnlyAccountIsClearedWithoutAServerCall() async throws {
        let d = UserDefaults.standard
        d.set(true, forKey: "auth.isSignedIn")
        d.set("email", forKey: "auth.provider")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter)

        try await manager.deleteAccount(appleReauth: nil)

        #expect(deleter.calls.isEmpty)
        #expect(!manager.isSignedIn)
    }
```

(c) Add the fake at the bottom of the file, next to `FakeSupabaseAuthenticating`:
```swift
private final class FakeAccountDeleter: SupabaseAccountDeleting, @unchecked Sendable {
    var result: Result<Void, Error> = .success(())
    private(set) var calls: [String?] = []

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        calls.append(appleAuthorizationCode)
        try result.get()
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests/AuthManagerTests"`
Expected: a compile failure. There's no `accountDeleter:` init parameter, and `AppleReauthCredential` isn't found.

- [ ] **Step 3: Implement in `AuthManager.swift`**

(a) Above `// MARK: - Auth Provider` (near the top of the file), add:
```swift
/// What the Sign in with Apple re-confirm sheet hands back before Delete
/// Account (see AppleReauthenticator). `authorizationCode` is the one-time
/// code the server trades with Apple to revoke this app's authorization;
/// `identityToken` + `rawNonce` let a user whose original Supabase exchange
/// failed get a session first; `appleUserID` locates the cached Apple email.
nonisolated struct AppleReauthCredential: Sendable, Equatable {
    let appleUserID: String
    let authorizationCode: String
    let identityToken: String
    let rawNonce: String?
}
```

(b) Add a stored property next to `private let supabase: SupabaseAuthenticating`:
```swift
    private let accountDeleter: SupabaseAccountDeleting
```

(c) Replace the init:
```swift
    init(
        keychain: KeychainStore = SecItemKeychainStore(service: "com.breathapp.auth"),
        supabase: SupabaseAuthenticating = SupabaseService.shared,
        accountDeleter: SupabaseAccountDeleting = SupabaseService.shared
    ) {
        self.keychain = keychain
        self.supabase = supabase
        self.accountDeleter = accountDeleter
        loadPersistedState()
    }
```

(d) Change `nonisolated private static func randomNonce(length: Int = 32) -> String` to `nonisolated static func randomNonce(length: Int = 32) -> String`. Only the `private` is dropped; the body stays the same.

(e) Replace the whole `// MARK: - Delete account` section (comment block + `func deleteAccount()`) with:
```swift
    // MARK: - Delete account
    // App Store Guideline 5.1.1(v): in-app deletion must delete the account
    // itself, and Sign in with Apple accounts must also have their Apple
    // authorization revoked. The delete-account Edge Function does both
    // server-side. Decision 2026-10-01: nothing local is cleared unless the
    // server confirms; on any failure this throws and the user stays signed
    // in to retry. The caller wipes local data (LocalDataEraser) after this
    // returns.

    func deleteAccount(appleReauth: AppleReauthCredential?) async throws {
        if provider == .apple && appleReauth == nil {
            throw AccountDeletionError.appleReauthRequired
        }

        if SupabaseService.isConfigured {
            // An Apple user whose original token exchange failed has no
            // stored Supabase id but may still have a server account. Get a
            // session from the fresh re-auth token first, never a local-only
            // delete that would orphan it.
            if !isBackendAuthenticated, let reauth = appleReauth {
                do {
                    let uid = try await supabase.signInWithApple(
                        identityToken: reauth.identityToken, nonce: reauth.rawNonce)
                    UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
                } catch {
                    throw AccountDeletionError.server
                }
            }
            // Not backend-authenticated here means the account never existed
            // server-side, so there's nothing remote to delete.
            if isBackendAuthenticated {
                try await accountDeleter.deleteAccount(
                    appleAuthorizationCode: appleReauth?.authorizationCode)
            }
        }

        // Server confirmed (or there was no server account). Clear auth state.
        if let appleUserID = appleReauth?.appleUserID {
            keychain.delete(account: "apple-email:\(appleUserID)")
        }
        let d = UserDefaults.standard
        d.removeObject(forKey: kTwoFAEnabled)
        d.removeObject(forKey: kAnonymousID)
        d.removeObject(forKey: kSupabaseUserID)
        backendSyncFailed = false
        pendingAppleRetry = nil
        clearLocalSignIn()
        objectWillChange.send() // backendID/isBackendAuthenticated changed
    }
```

- [ ] **Step 4: Make the old call site compile (temporary)**

`ProfileAccountTab.swift` line ~111 still calls `auth.deleteAccount()`. Change that one line to the following so the target builds; Task 6 replaces it:
```swift
            Button("Delete Account", role: .destructive) { Task { try? await auth.deleteAccount(appleReauth: nil) } }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the Step 2 command.
Expected: all `AuthManagerTests` pass, including the 7 new ones.

- [ ] **Step 6: Commit**

```bash
git add "Breath - Relax & Stretch/Services/AuthManager.swift" "Breath - Relax & Stretch/Views/Profile/ProfileAccountTab.swift" "Breath - Relax & StretchTests/AuthManagerTests.swift"
git commit -m "feat: AuthManager.deleteAccount deletes server-side first, fails closed

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Apple re-confirm sheet + Delete Account UI

**Files:**
- Create: `Breath - Relax & Stretch/Services/AppleReauthenticator.swift`
- Modify: `Breath - Relax & Stretch/Views/Profile/ProfileAccountTab.swift`

**Interfaces:**
- Consumes: `AppleReauthCredential`, `AuthManager.randomNonce()`, `AuthManager.deleteAccount(appleReauth:)` (Task 5), `LocalDataEraser.eraseAll(context:)` (Task 4), `AccountDeletionError` (Task 3), `NotificationService.shared.cancelReminders()` and `.cancelInsightNotifications()` (existing).
- Produces: `final class AppleReauthenticator { func reauthenticate() async throws -> AppleReauthCredential }`. It throws `CancellationError` when the user dismisses the sheet.

This task is UI glue around system sheets, so there's no unit test. It's verified by build plus simulator in Steps 4–5.

- [ ] **Step 1: Implement `AppleReauthenticator`**

```swift
import AuthenticationServices
import CryptoKit
import UIKit

/// Shows the Sign in with Apple sheet without a SignInWithAppleButton, so
/// Delete Account can ask an Apple user to re-confirm. The fresh one-time
/// authorization code it returns is what the delete-account function
/// needs to revoke the app's Apple authorization (Guideline 5.1.1(v)).
final class AppleReauthenticator: NSObject,
    @preconcurrency ASAuthorizationControllerDelegate,
    @preconcurrency ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleReauthCredential, Error>?
    private var rawNonce: String?

    func reauthenticate() async throws -> AppleReauthCredential {
        let raw = AuthManager.randomNonce()
        rawNonce = raw
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [] // re-confirm only; no name/email needed
        request.nonce = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8),
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            finish(.failure(AccountDeletionError.appleReauthRequired))
            return
        }
        finish(.success(AppleReauthCredential(
            appleUserID: credential.user, authorizationCode: code,
            identityToken: token, rawNonce: rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(AccountDeletionError.appleReauthRequired))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<AppleReauthCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        rawNonce = nil
    }
}
```

- [ ] **Step 2: Wire up `ProfileAccountTab`**

(a) Add the environment and state next to the existing `@EnvironmentObject private var auth: AuthManager` and the other `@State` properties:
```swift
    @Environment(\.modelContext) private var modelContext
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
```

(b) Replace the Delete Account row's `Button` (the one that sets `showDeleteConfirm = true`) with a version that shows progress and can't be double-tapped:
```swift
                if auth.isSignedIn && !auth.isGuest {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash")
                            if isDeletingAccount {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                }
```

(c) Replace the whole `.confirmationDialog(...)` modifier with:
```swift
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await performAccountDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your progress and leaderboard entry on our servers, and all app data on this iPhone, including session history, routines, and body-map marks. This can't be undone.")
        }
        .alert(
            "Couldn't Delete Account",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
```

(d) Add this helper in the `// MARK: Helpers` section:
```swift
    /// Apple users re-confirm first (Apple's revoke needs a fresh code).
    /// Only after the server confirms is anything local touched; a cancelled
    /// sheet is silent, and any other failure shows why and leaves the user
    /// signed in to retry.
    private func performAccountDeletion() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            let reauth: AppleReauthCredential? = auth.provider == .apple
                ? try await AppleReauthenticator().reauthenticate()
                : nil
            try await auth.deleteAccount(appleReauth: reauth)
            NotificationService.shared.cancelReminders()
            NotificationService.shared.cancelInsightNotifications()
            try? LocalDataEraser.eraseAll(context: modelContext)
        } catch is CancellationError {
            // User dismissed the Apple sheet. Nothing to report.
        } catch {
            deleteError = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Build and run the full unit suite**

Run: `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests"`
Expected: the build succeeds and every new suite passes. Per project memory, `CuratedContentIntegrityTests` failures already exist and aren't regressions. Compare against `main` if anything else fails.

- [ ] **Step 4: Simulator check, failure path (no backend needed)**

Use the repo's `.claude/skills/verify/SKILL.md` recipe. Sign up with a test email account, turn on Airplane-equivalent conditions (Network Link Conditioner "100% Loss", or simply run this before Task 7 deploys the function, so the call 404s and maps to `.server`), then tap Profile → Account → Delete Account → Delete Account.
Expected: a spinner, then the "Couldn't Delete Account" alert. The user is **still signed in** and their history is intact.

- [ ] **Step 5: Simulator check, the copy and the double-tap guard**

Expected: the dialog shows the new "permanently deletes…" text, and while the spinner shows, the row is disabled.

- [ ] **Step 6: Update the graph and commit**

```bash
graphify update .
git add "Breath - Relax & Stretch/Services/AppleReauthenticator.swift" "Breath - Relax & Stretch/Views/Profile/ProfileAccountTab.swift" "Breath - Relax & Stretch/Resources/Localizable.xcstrings"
git commit -m "feat: Delete Account re-confirms Apple users, shows progress and errors, wipes local data

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Deploy, live test, docs (requires Jason)

Everything in this task touches live systems or real secrets, so **each step needs Jason's go-ahead or is done by Jason**.

- [ ] **Step 1 (Jason): Set the secrets.** Run these from the repo root. The `.p8` path is wherever you keep the Sign in with Apple key; don't copy it into the repo.

```bash
supabase secrets set --project-ref wmsutfittuxrvcwuywrk \
  APPLE_TEAM_ID=F4NF2ZRZS9 \
  APPLE_CLIENT_ID=com.jasonlu.Dial--Down--Breath--Stretch \
  APPLE_SIWA_KEY_ID=<your Sign in with Apple Key ID>
supabase secrets set --project-ref wmsutfittuxrvcwuywrk \
  APPLE_SIWA_KEY_P8="$(cat /path/to/AuthKey_XXXXXXXXXX.p8)"
```

Use the **Sign in with Apple** key's ID, not the APNs key `N7992N49CB`, unless that one key has both capabilities enabled in the Apple Developer portal.

- [ ] **Step 2 (after go-ahead): Deploy.** Run `supabase functions deploy delete-account --project-ref wmsutfittuxrvcwuywrk`.

- [ ] **Step 3: Live test, email account.** On a simulator, create a throwaway email account and complete the name step. Then delete it.
Expected: the app goes back to onboarding. In the Supabase dashboard, the user is gone from Authentication → Users and there's no `profiles` row with that id.

- [ ] **Step 4: Live test, Apple account (needs a real device or a simulator signed into an Apple ID).** Sign in with Apple, then delete.
Expected: the Apple sheet appears, then the app returns to onboarding. On the device, Settings → Apple ID → Sign-In & Security → Sign in with Apple no longer lists Dial Down. The function logs show no errors.

- [ ] **Step 5: Correct the privacy policy's deletion section**

In `Breath - Relax & Stretch/Legal/PrivacyPolicy.html`, replace the body of `<h2>8. Data Retention and Deletion</h2>`:
```html
  <p>
    Locally stored data remains on your device until you delete it or the App. You can delete your
    account at any time in Profile &rarr; Account &rarr; Delete Account. This permanently deletes
    your account, your profile, leaderboard entry, and reminder registration from our servers,
    revokes Sign in with Apple if you used it, and erases the App's data on your device. You can
    also request deletion by contacting us (see below).
  </p>
```

- [ ] **Step 6: Update the tracking docs.** In `TODO.md` §6, remove the "Apple Sign-in server-to-server notifications" note *only if* Jason decides it's no longer wanted. That's a separate feature for when users revoke from iOS Settings, and it's not required for this. In `docs/APP_STORE_READINESS-2026-09-08.md`, add a line under the blockers that account deletion is now complete server-side, dated the day it ships.

- [ ] **Step 7: Commit**

```bash
git add "Breath - Relax & Stretch/Legal/PrivacyPolicy.html" TODO.md docs/APP_STORE_READINESS-2026-09-08.md
git commit -m "docs: privacy policy and readiness doc reflect full account deletion

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
