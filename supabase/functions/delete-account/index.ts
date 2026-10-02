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
import { resolveCaller } from "./caller.ts";
import { revokeAppleAuthorization } from "./apple.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// [table, owner column]. None of these has a foreign key to auth.users
// (see supabase_schema.sql), so deleting the auth user would NOT cascade.
// Each one is removed explicitly (and swept again after the auth delete —
// see handler.ts). push_tokens goes first so the streak cron
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
    resolveCaller: (jwt) =>
      resolveCaller(jwt, {
        async getUser(token) {
          const { data, error } = await admin.auth.getUser(token);
          return { user: data.user, error: error ? { status: error.status, code: error.code } : null };
        },
        async userExists(userID) {
          const { data, error } = await admin.auth.admin.getUserById(userID);
          if (data.user) return true;
          if (error && (error.status === 404 || error.code === "user_not_found")) return false;
          throw error ?? new Error("getUserById returned neither a user nor an error");
        },
      }),
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
