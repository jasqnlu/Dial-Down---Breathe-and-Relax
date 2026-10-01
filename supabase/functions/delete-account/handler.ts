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
