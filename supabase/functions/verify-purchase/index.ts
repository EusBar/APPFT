// Confirma uma compra do FINTRACK Premium junto da loja e guarda a validade.
//
// O telemóvel envia o comprovativo da loja; este servidor pergunta à Google
// Play ou à Apple se a subscrição é verdadeira e até quando é válida. Assim
// ninguém desbloqueia o Premium sem pagar, e a subscrição acompanha a conta
// em todos os telemóveis.
//
// Segredos (Supabase → Edge Functions → Secrets), só depois de haver lojas:
//   GOOGLE_SERVICE_ACCOUNT  JSON da conta de serviço com acesso à Play Console
//   APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY  chave da App Store Connect API
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PACKAGE = "ao.fintrack.fintrack";
const BUNDLE = "ao.fintrack.fintrack";
const PRODUCTS = new Set(["fintrack_premium_monthly", "fintrack_premium_yearly"]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}

async function signJwt(header: object, payload: object, pem: string, alg: "RS256" | "ES256") {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    alg === "RS256" ? { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" } : { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = await crypto.subtle.sign(
    alg === "RS256" ? "RSASSA-PKCS1-v1_5" : { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(input),
  );
  return `${input}.${b64url(sig)}`;
}

function decodeJws(jws: string): Record<string, unknown> {
  const part = jws.split(".")[1];
  return JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
}

type Verified = { productId: string; originalId: string; expiresAt: Date };

// --- Google Play -------------------------------------------------------------
async function verifyGoogle(token: string): Promise<Verified | "invalid" | "not_configured"> {
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT");
  if (!raw) return "not_configured";
  const sa = JSON.parse(raw);
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 600,
    },
    sa.private_key,
    "RS256",
  );
  const tok = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!tok.ok) throw new Error(`google token ${tok.status}`);
  const { access_token } = await tok.json();
  const r = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`,
    { headers: { Authorization: `Bearer ${access_token}` } },
  );
  if (r.status === 404 || r.status === 400 || r.status === 410) return "invalid";
  if (!r.ok) throw new Error(`google verify ${r.status}`);
  const sub = await r.json();
  const state = sub.subscriptionState as string;
  if (!["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED"].includes(state)) {
    return "invalid";
  }
  const item = (sub.lineItems ?? []).find((l: { productId: string }) => PRODUCTS.has(l.productId));
  if (!item) return "invalid";
  return { productId: item.productId, originalId: sub.latestOrderId ?? token.slice(0, 120), expiresAt: new Date(item.expiryTime) };
}

// --- App Store -------------------------------------------------------------------
async function verifyApple(signedTransaction: string): Promise<Verified | "invalid" | "not_configured"> {
  const issuer = Deno.env.get("APPLE_ISSUER_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const pem = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!issuer || !keyId || !pem) return "not_configured";
  // Só se usa o identificador; a resposta que conta vem diretamente da Apple.
  let transactionId: string;
  try {
    transactionId = String(decodeJws(signedTransaction).originalTransactionId ?? decodeJws(signedTransaction).transactionId);
  } catch {
    return "invalid";
  }
  const now = Math.floor(Date.now() / 1000);
  const jwt = await signJwt(
    { alg: "ES256", kid: keyId, typ: "JWT" },
    { iss: issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1", bid: BUNDLE },
    pem,
    "ES256",
  );
  for (const host of ["api.storekit.itunes.apple.com", "api.storekit-sandbox.itunes.apple.com"]) {
    const r = await fetch(`https://${host}/inApps/v1/subscriptions/${transactionId}`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (r.status === 404) continue;
    if (!r.ok) throw new Error(`apple verify ${r.status}`);
    const data = await r.json();
    let best: Verified | null = null;
    for (const group of data.data ?? []) {
      for (const t of group.lastTransactions ?? []) {
        // 1 ativa, 3 nova tentativa de cobrança, 4 período de tolerância.
        if (![1, 3, 4].includes(t.status)) continue;
        const info = decodeJws(t.signedTransactionInfo);
        if (!PRODUCTS.has(String(info.productId)) || info.bundleId !== BUNDLE) continue;
        const exp = new Date(Number(info.expiresDate));
        if (!best || exp > best.expiresAt) {
          best = { productId: String(info.productId), originalId: String(info.originalTransactionId), expiresAt: exp };
        }
      }
    }
    return best ?? "invalid";
  }
  return "invalid";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!who.ok) return json({ error: "auth", message: "Entre na sua conta FINTRACK." }, 401);
  const user = await who.json();

  let body: { platform?: string; data?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const data = typeof body.data === "string" ? body.data : "";
  if (!data || data.length > 20000) return json({ error: "bad_request" }, 400);

  let result: Verified | "invalid" | "not_configured";
  try {
    result = body.platform === "ios" ? await verifyApple(data) : body.platform === "android" ? await verifyGoogle(data) : "invalid";
  } catch (e) {
    console.error("verify", e);
    return json({ error: "store", message: "A loja não respondeu. Tente de novo." }, 502);
  }
  if (result === "not_configured") return json({ error: "not_configured" }, 503);
  if (result === "invalid" || result.expiresAt.getTime() < Date.now()) {
    return json({ active: false });
  }

  const save = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?on_conflict=user_id`, {
    method: "POST",
    headers: {
      apikey: SERVICE,
      Authorization: `Bearer ${SERVICE}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify({
      user_id: user.id,
      platform: body.platform,
      product_id: result.productId,
      original_id: result.originalId,
      expires_at: result.expiresAt.toISOString(),
      updated_at: new Date().toISOString(),
    }),
  });
  if (!save.ok) {
    console.error("save", save.status, await save.text());
    return json({ error: "server" }, 502);
  }
  return json({ active: true, productId: result.productId, expiresAt: result.expiresAt.toISOString() });
});
