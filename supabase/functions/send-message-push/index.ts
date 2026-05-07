import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJwt, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';

type MessageRecord = {
  id: number;
  chat_id: number;
  sender_id: string;
  content: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
};

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const fcmServerKey = Deno.env.get('FCM_SERVER_KEY') ?? '';
const fcmServiceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';

const supabase = createClient(supabaseUrl, serviceRoleKey);

let cachedServiceAccount: ServiceAccount | null = null;
let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function loadServiceAccount(): ServiceAccount | null {
  if (cachedServiceAccount) return cachedServiceAccount;
  if (!fcmServiceAccountRaw) return null;
  try {
    const raw = fcmServiceAccountRaw.trim();
    const parsed = JSON.parse(raw) as ServiceAccount;
    cachedServiceAccount = parsed;
    return parsed;
  } catch (e) {
    console.error('FCM_SERVICE_ACCOUNT is not valid JSON:', e);
    return null;
  }
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\\n/g, '\n')
    .replace(/\s+/g, '');
  const binary = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    binary,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - 60 > now) {
    return cachedAccessToken.value;
  }
  const key = await importPrivateKey(account.private_key);
  const jwt = await createJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 50),
    },
    key,
  );

  const tokenUri = account.token_uri ?? 'https://oauth2.googleapis.com/token';
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(
      `Failed to get FCM access_token: ${res.status} ${JSON.stringify(data)}`,
    );
  }
  cachedAccessToken = {
    value: data.access_token,
    expiresAt: now + Number(data.expires_in ?? 3600),
  };
  return cachedAccessToken.value;
}

async function sendV1(
  account: ServiceAccount,
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<unknown[]> {
  const accessToken = await getAccessToken(account);
  const url = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  const results: unknown[] = [];
  for (const token of tokens) {
    const payload = {
      message: {
        token,
        notification: { title, body },
        data,
        android: { priority: 'HIGH', notification: { channel_id: 'high_importance_channel' } },
      },
    };
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    const text = await res.text();
    let parsed: unknown = text;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      // keep text
    }
    results.push({ status: res.status, body: parsed, token: token.slice(0, 12) + '…' });
    if (!res.ok) {
      console.error('FCM v1 send failed:', res.status, text);
    }
  }
  return results;
}

async function sendLegacy(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ status: number; raw: string; parsed: unknown }> {
  const res = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${fcmServerKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      registration_ids: tokens,
      notification: { title, body },
      data,
      priority: 'high',
    }),
  });
  const raw = await res.text();
  let parsed: unknown = raw;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    // keep raw
  }
  if (!res.ok) {
    console.error('FCM legacy send failed:', res.status, raw);
  }
  return { status: res.status, raw, parsed };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const account = loadServiceAccount();

  if (!account && !fcmServerKey) {
    return new Response(
      'No FCM credentials configured (set FCM_SERVICE_ACCOUNT or FCM_SERVER_KEY)',
      { status: 500 },
    );
  }

  const reqBody = await req.json().catch(() => ({}));
  const record = (reqBody.record ?? reqBody.newRecord ?? reqBody) as MessageRecord;

  if (!record?.chat_id || !record?.sender_id || !record?.content) {
    return new Response('Invalid Message payload', { status: 400 });
  }

  const { data: members, error: membersError } = await supabase
    .from('ChatMember')
    .select('user_id')
    .eq('chat_id', record.chat_id)
    .neq('user_id', record.sender_id);

  if (membersError) throw membersError;

  const userIds = [...new Set((members ?? []).map((m) => m.user_id as string))];
  if (userIds.length === 0) {
    return Response.json({ sent: 0, reason: 'no_other_members' });
  }

  const [{ data: prefs }, { data: muted }, { data: tokens }, { data: chat }] =
    await Promise.all([
      supabase
        .from('NotificationPreference')
        .select('user_id, chats_enabled')
        .in('user_id', userIds),
      supabase
        .from('ChatNotificationMute')
        .select('user_id')
        .eq('chat_id', record.chat_id)
        .in('user_id', userIds),
      supabase
        .from('DevicePushToken')
        .select('user_id, token')
        .in('user_id', userIds),
      supabase
        .from('Chat')
        .select('namechat')
        .eq('id', record.chat_id)
        .maybeSingle(),
    ]);

  const disabled = new Set(
    (prefs ?? [])
      .filter((p) => p.chats_enabled === false)
      .map((p) => p.user_id as string),
  );
  const mutedUsers = new Set((muted ?? []).map((m) => m.user_id as string));
  const targetTokens = (tokens ?? [])
    .filter((t) => !disabled.has(t.user_id as string))
    .filter((t) => !mutedUsers.has(t.user_id as string))
    .map((t) => t.token as string);

  if (targetTokens.length === 0) {
    return Response.json({
      sent: 0,
      reason: 'no_tokens_after_filter',
      candidates: userIds.length,
      tokens_total: tokens?.length ?? 0,
      muted: mutedUsers.size,
      disabled: disabled.size,
    });
  }

  const preview = record.content.replace(/^GHMSG:/, '').slice(0, 120);
  const title = chat?.namechat ?? 'Новое сообщение';
  const data = {
    type: 'new_message',
    chat_id: `${record.chat_id}`,
    message_id: `${record.id}`,
  };

  try {
    if (account) {
      const results = await sendV1(account, targetTokens, title, preview, data);
      return Response.json({
        provider: 'fcm_v1',
        sent: targetTokens.length,
        results,
      });
    }
    const legacy = await sendLegacy(targetTokens, title, preview, data);
    return Response.json({
      provider: 'fcm_legacy',
      sent: targetTokens.length,
      ...legacy,
    });
  } catch (e) {
    console.error('Push send failed:', e);
    return Response.json(
      { error: String(e), sent: 0, attempted: targetTokens.length },
      { status: 500 },
    );
  }
});
