// supabase/functions/delete-account/caller.ts
//
// Works out who is calling from their access token, distinguishing three
// outcomes the handler treats differently:
//
//   active   — a live account: go ahead and delete it.
//   deleted  — the token is genuine but its user no longer exists. This is
//              a retry after a delete whose 200 never reached the app, so
//              the handler sweeps any leftover rows and reports success
//              instead of stranding the user on "session expired".
//   null     — not a valid token: 401.
//
// Transient failures (auth server 5xx, network) THROW so the handler
// returns a retryable 500 rather than a misleading 401.
//
// Trust: GoTrue's /user endpoint validates the token's signature before it
// looks the user up, so a `user_not_found` / `session_not_found` error means
// the token was authentic and its `sub` can be read. Even then, the account
// is only treated as deleted after an admin lookup confirms it's gone, so a
// signed-out session of a live account can never take the "deleted" path.

export type Caller =
  | { state: "active"; id: string; providers: string[] }
  | { state: "deleted"; id: string };

export interface AuthLookup {
  /** Shape of supabase-js `auth.getUser(jwt)`, narrowed to what's used. */
  getUser(jwt: string): Promise<{
    user: { id: string; app_metadata?: Record<string, unknown> } | null;
    error: { status?: number; code?: string } | null;
  }>;
  /** Admin lookup by id; throws on transient failure. */
  userExists(userID: string): Promise<boolean>;
}

const GENUINE_TOKEN_MISSING_USER = new Set(["user_not_found", "session_not_found"]);

/** The `sub` claim of a JWT, or null if the token can't be decoded. Does NOT verify. */
export function jwtSubject(jwt: string): string | null {
  const payload = jwt.split(".")[1];
  if (!payload) return null;
  try {
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    return typeof claims?.sub === "string" && claims.sub.length > 0 ? claims.sub : null;
  } catch {
    return null;
  }
}

function providersOf(meta: Record<string, unknown> | undefined): string[] {
  if (Array.isArray(meta?.providers)) {
    return meta.providers.filter((p): p is string => typeof p === "string");
  }
  return typeof meta?.provider === "string" ? [meta.provider] : [];
}

export async function resolveCaller(jwt: string, api: AuthLookup): Promise<Caller | null> {
  const { user, error } = await api.getUser(jwt);
  if (user && !error) {
    return { state: "active", id: user.id, providers: providersOf(user.app_metadata) };
  }

  const status = error?.status ?? 0;
  if (status === 0 || status >= 500) {
    throw new Error(`auth lookup failed (status ${status}, ${error?.code ?? "no code"})`);
  }

  if (error?.code && GENUINE_TOKEN_MISSING_USER.has(error.code)) {
    const sub = jwtSubject(jwt);
    if (!sub) return null;
    return (await api.userExists(sub)) ? null : { state: "deleted", id: sub };
  }

  return null;
}
