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
    // A .p8 pasted into a secret store can arrive with literal "\n" text.
    .replace(/\\n/g, "")
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
