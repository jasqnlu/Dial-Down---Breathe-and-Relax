import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { type AuthLookup, jwtSubject, resolveCaller } from "./caller.ts";

// A token whose payload is {"sub": <sub>}. resolveCaller only decodes the
// payload after GoTrue has already validated the signature (see caller.ts),
// so these tests don't need a real signature.
function tokenFor(sub: string): string {
  const b64 = (s: string) =>
    btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${b64('{"alg":"HS256"}')}.${b64(JSON.stringify({ sub }))}.sig`;
}

type GetUserResult = Awaited<ReturnType<AuthLookup["getUser"]>>;

function lookup(getUser: GetUserResult, userExists: boolean | Error = false) {
  const existsCalls: string[] = [];
  const api: AuthLookup = {
    getUser: async () => getUser,
    userExists: async (id) => {
      existsCalls.push(id);
      if (userExists instanceof Error) throw userExists;
      return userExists;
    },
  };
  return { api, existsCalls };
}

Deno.test("jwtSubject reads sub from the payload", () => {
  assertEquals(jwtSubject(tokenFor("u-123")), "u-123");
});

Deno.test("jwtSubject returns null for garbage", () => {
  assertEquals(jwtSubject("not-a-jwt"), null);
  assertEquals(jwtSubject("a.%%%.c"), null);
  assertEquals(jwtSubject(`a.${btoa("{}")}.c`), null);
});

Deno.test("a live user is active, with their providers", async () => {
  const { api } = lookup({
    user: { id: "u1", app_metadata: { providers: ["email", "apple"] } },
    error: null,
  });
  assertEquals(await resolveCaller("t", api), {
    state: "active", id: "u1", providers: ["email", "apple"],
  });
});

Deno.test("a single legacy provider string is accepted", async () => {
  const { api } = lookup({ user: { id: "u1", app_metadata: { provider: "apple" } }, error: null });
  assertEquals(await resolveCaller("t", api), { state: "active", id: "u1", providers: ["apple"] });
});

Deno.test("a valid token for a user that no longer exists is 'deleted'", async () => {
  const { api, existsCalls } = lookup(
    { user: null, error: { status: 403, code: "user_not_found" } },
    false,
  );
  assertEquals(await resolveCaller(tokenFor("gone-1"), api), { state: "deleted", id: "gone-1" });
  assertEquals(existsCalls, ["gone-1"]);
});

Deno.test("session_not_found for a user who still exists is NOT 'deleted'", async () => {
  // A signed-out session of a live account must never be treated as deleted.
  const { api } = lookup(
    { user: null, error: { status: 403, code: "session_not_found" } },
    true,
  );
  assertEquals(await resolveCaller(tokenFor("u1"), api), null);
});

Deno.test("an invalid token is unauthorized and never looks the user up", async () => {
  const { api, existsCalls } = lookup({ user: null, error: { status: 401, code: "bad_jwt" } });
  assertEquals(await resolveCaller(tokenFor("u1"), api), null);
  assertEquals(existsCalls, []);
});

Deno.test("user_not_found with an undecodable token is unauthorized", async () => {
  const { api } = lookup({ user: null, error: { status: 403, code: "user_not_found" } });
  assertEquals(await resolveCaller("garbage", api), null);
});

Deno.test("an auth-server 5xx throws instead of looking like a bad token", async () => {
  const { api } = lookup({ user: null, error: { status: 503, code: "unexpected_failure" } });
  await assertRejects(() => resolveCaller("t", api));
});

Deno.test("a network failure (no status) throws", async () => {
  const { api } = lookup({ user: null, error: { status: 0, code: undefined } });
  await assertRejects(() => resolveCaller("t", api));
});

Deno.test("a failing existence check throws instead of guessing", async () => {
  const { api } = lookup(
    { user: null, error: { status: 403, code: "user_not_found" } },
    new Error("admin api down"),
  );
  await assertRejects(() => resolveCaller(tokenFor("u1"), api));
});
