import { assertEquals } from "jsr:@std/assert@1";
import { type Caller, type DeleteAccountDeps, handleDeleteAccount } from "./handler.ts";

type User = { id: string; providers: string[] };

/** A plain {id, providers} is shorthand for an active caller. */
function fakeDeps(user: User | Caller | null, overrides: Partial<DeleteAccountDeps> = {}) {
  const log: string[] = [];
  const caller: Caller | null = user && !("state" in user)
    ? { state: "active", ...user }
    : user;
  const deps: DeleteAccountDeps = {
    resolveCaller: async (jwt) => { log.push(`resolveCaller:${jwt}`); return caller; },
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
  assertEquals(log, ["resolveCaller:user-jwt"]);
});

Deno.test("email user: rows, auth user, then a sweep for late inserts; no Apple call", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email"] });
  const res = await handleDeleteAccount(post(), deps); // empty body is fine
  assertEquals(await status(res), [200, { deleted: true }]);
  assertEquals(log, [
    "resolveCaller:user-jwt", "deleteUserRows:u1", "deleteAuthUser:u1", "deleteUserRows:u1",
  ]);
});

Deno.test("apple user without a code is told to re-authenticate; nothing deleted", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["apple"] });
  const res = await handleDeleteAccount(post({}), deps);
  assertEquals(await status(res), [400, { error: "apple_reauth_required" }]);
  assertEquals(log, ["resolveCaller:user-jwt"]);
});

Deno.test("apple user: revoke happens BEFORE any deletion", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["email", "apple"] });
  const res = await handleDeleteAccount(post({ apple_authorization_code: "c1" }), deps);
  assertEquals(await status(res), [200, { deleted: true }]);
  assertEquals(log, [
    "resolveCaller:user-jwt", "revokeApple:c1",
    "deleteUserRows:u1", "deleteAuthUser:u1", "deleteUserRows:u1",
  ]);
});

Deno.test("apple revoke failure is a 502 and nothing is deleted", async () => {
  const { deps, log } = fakeDeps({ id: "u1", providers: ["apple"] }, {
    revokeApple: async () => { throw new Error("apple down"); },
  });
  const res = await handleDeleteAccount(post({ apple_authorization_code: "c1" }), deps);
  assertEquals(await status(res), [502, { error: "apple_revoke_failed" }]);
  assertEquals(log, ["resolveCaller:user-jwt"]);
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

Deno.test("an already-deleted caller (lost 200, retried) sweeps leftovers and succeeds", async () => {
  const { deps, log } = fakeDeps({ state: "deleted", id: "u1" });
  // An Apple user's retry still sends a code; it must not be used.
  const res = await handleDeleteAccount(post({ apple_authorization_code: "c1" }), deps);
  assertEquals(await status(res), [200, { deleted: true }]);
  assertEquals(log, ["resolveCaller:user-jwt", "deleteUserRows:u1"]);
});

Deno.test("an already-deleted caller whose sweep fails gets a 500 to retry", async () => {
  const { deps } = fakeDeps({ state: "deleted", id: "u1" }, {
    deleteUserRows: async () => { throw new Error("db down"); },
  });
  const res = await handleDeleteAccount(post(), deps);
  assertEquals(await status(res), [500, { error: "delete_failed" }]);
});

Deno.test("a transient failure resolving the caller is a 500, not a 401, and deletes nothing", async () => {
  const { deps, log } = fakeDeps(null, {
    resolveCaller: async () => { throw new Error("auth server 503"); },
  });
  const res = await handleDeleteAccount(post(), deps);
  assertEquals(await status(res), [500, { error: "delete_failed" }]);
  assertEquals(log, []);
});

Deno.test("a failed post-delete sweep is a 500 so the client retries into the deleted path", async () => {
  let rowCalls = 0;
  const { deps } = fakeDeps({ id: "u1", providers: ["email"] }, {
    deleteUserRows: async () => { if (++rowCalls === 2) throw new Error("db blip"); },
  });
  const res = await handleDeleteAccount(post(), deps);
  assertEquals(await status(res), [500, { error: "delete_failed" }]);
});
