require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');
const { GoogleGenAI } = require('@google/genai');

const PLAID_ENV = process.env.PLAID_ENV || 'sandbox';
const KEY = Buffer.from(process.env.STORAGE_ENCRYPTION_KEY || '', 'hex');
if (KEY.length !== 32) {
  console.error('STORAGE_ENCRYPTION_KEY must be a 64-character hex string (32 bytes). Refusing to start.');
  process.exit(1);
}

const client = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments[PLAID_ENV],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
      'PLAID-SECRET': process.env.PLAID_SECRET,
    },
  },
}));

// --- Local encrypted storage for Plaid items (one per linked bank) ---
// Single-user, local-only store. Not designed for multi-tenant or hosted use.
const DATA_DIR = path.join(__dirname, 'data');
const STORE_PATH = path.join(DATA_DIR, 'items.enc.json');

function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', KEY, iv);
  const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), enc]).toString('base64');
}
function decrypt(payload) {
  const buf = Buffer.from(payload, 'base64');
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const enc = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', KEY, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}
// --- Where things are kept ----------------------------------------------------
// A file, locally. On a host with an ephemeral filesystem — Render's free tier wipes it on
// every spin-down and every deploy — a file would mean re-linking every bank after each quiet
// spell, so a key/value store takes over when one is configured. What gets written is the same
// text either way: access tokens are encrypted before they leave this process, so the store
// never holds one in the clear.
const KV_URL = (process.env.KV_REST_API_URL || '').replace(/\/+$/, '');
const KV_TOKEN = process.env.KV_REST_API_TOKEN || '';
const KV_ENABLED = Boolean(KV_URL && KV_TOKEN);

async function readBlob(name, filePath) {
  if (!KV_ENABLED) {
    if (!fs.existsSync(filePath)) return null;
    return fs.readFileSync(filePath, 'utf8').trim() || null;
  }
  const response = await fetch(`${KV_URL}/get/${encodeURIComponent(name)}`, {
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  if (!response.ok) throw new Error(`Key/value store answered ${response.status} reading ${name}`);
  const body = await response.json();
  return body.result || null;
}

async function writeBlob(name, filePath, text) {
  if (!KV_ENABLED) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(filePath, text);
    return;
  }
  const response = await fetch(`${KV_URL}/set/${encodeURIComponent(name)}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
    body: text,
  });
  if (!response.ok) throw new Error(`Key/value store answered ${response.status} writing ${name}`);
}

async function loadItems() {
  const raw = await readBlob('items', STORE_PATH);
  if (!raw) return [];
  return JSON.parse(raw).map((item) => ({ ...item, accessToken: decrypt(item.accessToken) }));
}
async function saveItems(items) {
  const encoded = items.map((item) => ({ ...item, accessToken: encrypt(item.accessToken) }));
  await writeBlob('items', STORE_PATH, JSON.stringify(encoded, null, 2));
}

// Plaid: positive amount = money out of the account (expense), negative = money in (income).
function normalize(t, institutionName) {
  return {
    id: t.transaction_id,
    merchant: t.merchant_name || t.name,
    amountCents: Math.round(Math.abs(t.amount) * 100),
    kind: t.amount > 0 ? 'expense' : 'income',
    date: t.date,
    // Only some institutions send a clock time, and some of those send a midnight placeholder.
    // authorized_datetime is when the card was actually used; datetime is when it posted.
    datetime: t.authorized_datetime || t.datetime || null,
    category: t.personal_finance_category?.primary || t.category?.[0] || null,
    // The primary category lumps tuition, insurance and subscriptions together under
    // GENERAL_SERVICES; the detailed one tells them apart.
    categoryDetailed: t.personal_finance_category?.detailed || null,
    institution: institutionName,
    pending: t.pending,
  };
}

// A credit card's official_name ("American Express® Gold Card") is what identifies the product,
// and so what its earn rates can be looked up against. transactionsSync already returns it.
function normalizeAccount(a, institutionName) {
  return {
    accountId: a.account_id,
    name: a.name,
    officialName: a.official_name || null,
    mask: a.mask || null,
    subtype: a.subtype || null,
    isCreditCard: a.type === 'credit',
    institution: institutionName,
  };
}

// --- Access control -----------------------------------------------------------
// Every /api route reads or changes real bank data, so all of them require a shared token.
// It is generated on first run and kept in data/, because a backend that is safe only while
// nobody knows its address is not safe at all — and the moment this is reachable from a
// tunnel or a host, the address is the only thing standing between a stranger and a full
// transaction history.
const ACCESS_TOKEN_PATH = path.join(DATA_DIR, 'access-token.txt');

function loadAccessToken() {
  const configured = (process.env.BACKEND_ACCESS_TOKEN || '').trim();
  if (configured) return configured;
  if (fs.existsSync(ACCESS_TOKEN_PATH)) {
    const stored = fs.readFileSync(ACCESS_TOKEN_PATH, 'utf8').trim();
    if (stored) return stored;
  }
  const minted = crypto.randomBytes(16).toString('hex');
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(ACCESS_TOKEN_PATH, minted + '\n', { mode: 0o600 });
  return minted;
}

const ACCESS_TOKEN = loadAccessToken();

// A minted token lives in data/, which a host with an ephemeral filesystem throws away — so
// every restart would mint a different one and every app paired with it would start being
// refused, for no visible reason. If this is configured for a host, the token must come from
// the environment too.
if (KV_ENABLED && !(process.env.BACKEND_ACCESS_TOKEN || '').trim()) {
  console.error('BACKEND_ACCESS_TOKEN must be set when a key/value store is configured, or the');
  console.error('token changes on every restart and the app stops being able to connect.');
  console.error('Generate one with:  node -e "console.log(require(\'crypto\').randomBytes(16).toString(\'hex\'))"');
  process.exit(1);
}

function presentedToken(req) {
  const header = req.get('authorization') || '';
  if (header.toLowerCase().startsWith('bearer ')) return header.slice(7).trim();
  return (req.get('x-samgloyim-token') || '').trim();
}

// Compared byte-for-byte in constant time: a comparison that bails on the first wrong
// character leaks the token one character at a time to anyone patient enough to measure.
function authorized(req) {
  const given = Buffer.from(presentedToken(req), 'utf8');
  const expected = Buffer.from(ACCESS_TOKEN, 'utf8');
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

const app = express();
app.use(cors());
app.use(express.json());

app.use('/api', (req, res, next) => {
  if (authorized(req)) return next();
  res.status(401).json({
    error: 'This backend needs its access token. Copy it from the terminal running `npm start` into the app under Import \u203a Sync server.',
  });
});

// READ-ONLY BY DESIGN. Do not add 'auth', 'transfer', 'payment_initiation', 'processor',
// or any other money-movement product to this array. This item is only ever enrolled in
// 'transactions', which means the resulting access_token cannot be used to move, authorize,
// or initiate any transfer — Plaid rejects calls to products an item isn't enrolled in. This
// app has no code path that calls a payment/transfer endpoint, and it must stay that way.
const PLAID_PRODUCTS = ['transactions'];

app.post('/api/create_link_token', async (req, res) => {
  try {
    const response = await client.linkTokenCreate({
      user: { client_user_id: 'samgloyim-local-user' },
      client_name: 'samgloyim',
      products: PLAID_PRODUCTS,
      country_codes: ['US'],
      language: 'en',
    });
    res.json({ link_token: response.data.link_token });
  } catch (err) {
    console.error(err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to create link token' });
  }
});

app.post('/api/exchange_public_token', async (req, res) => {
  const { public_token, institution_name } = req.body;
  if (!public_token) return res.status(400).json({ error: 'public_token required' });
  try {
    const response = await client.itemPublicTokenExchange({ public_token });
    const items = await loadItems();
    items.push({
      itemId: response.data.item_id,
      accessToken: response.data.access_token,
      institutionName: institution_name || 'Linked bank',
      cursor: null,
      linkedAt: new Date().toISOString(),
    });
    await saveItems(items);
    res.json({ item_id: response.data.item_id, institution_name: institution_name || 'Linked bank' });
  } catch (err) {
    console.error(err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to exchange public token' });
  }
});

app.get('/api/items', async (req, res) => {
  const items = await loadItems();
  res.json(items.map(({ itemId, institutionName, linkedAt }) => ({ itemId, institutionName, linkedAt })));
});

app.delete('/api/items/:itemId', async (req, res) => {
  const items = await loadItems();
  const target = items.find((i) => i.itemId === req.params.itemId);
  if (!target) return res.status(404).json({ error: 'Not found' });
  try {
    await client.itemRemove({ access_token: target.accessToken });
  } catch (err) {
    console.error(err.response?.data || err.message);
  }
  await saveItems(items.filter((i) => i.itemId !== req.params.itemId));
  res.json({ ok: true });
});

app.get('/api/transactions', async (req, res) => {
  try {
    const items = await loadItems();
    if (items.length === 0) return res.json({ accounts: [], added: [], modified: [], removed: [] });

    let added = [];
    let modified = [];
    let removed = [];
    let accounts = [];
    const updatedItems = [];

    for (const item of items) {
      let cursor = item.cursor || undefined;
      let hasMore = true;
      while (hasMore) {
        const resp = await client.transactionsSync({ access_token: item.accessToken, cursor });
        for (const account of resp.data.accounts.map((a) => normalizeAccount(a, item.institutionName))) {
          if (!accounts.some((existing) => existing.accountId === account.accountId)) accounts.push(account);
        }
        added = added.concat(resp.data.added.map((t) => normalize(t, item.institutionName)));
        modified = modified.concat(resp.data.modified.map((t) => normalize(t, item.institutionName)));
        removed = removed.concat(resp.data.removed.map((t) => t.transaction_id));
        cursor = resp.data.next_cursor;
        hasMore = resp.data.has_more;
      }
      updatedItems.push({ ...item, cursor });
    }

    await saveItems(updatedItems);
    res.json({ accounts, added, modified, removed });
  } catch (err) {
    console.error(err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to sync transactions' });
  }
});

// --- Card reward rates ---------------------------------------------------
// Nothing publishes earn rates as an API, but every issuer publishes them on the open web, and
// Discover-style rotating categories change every quarter. So the rates are looked up live for
// whatever card the bank reports, rather than baked into the app for a fixed list of products.
// Answers are cached on disk: a card's rates are worth re-checking occasionally, not every launch.
const REWARDS_PATH = path.join(DATA_DIR, 'rewards.json');
const REWARDS_TTL_DAYS = 14;
const CATEGORIES = ['Food & drink', 'Groceries', 'Transport', 'Travel', 'Shopping', 'Education', 'Home & bills',
  'Entertainment', 'Subscriptions', 'Health', 'Personal care', 'People', 'Fees & interest', 'Government', 'Services', 'Other'];

async function loadRewards() {
  try {
    const raw = await readBlob('rewards', REWARDS_PATH);
    return raw ? JSON.parse(raw) : {};
  } catch {
    // A cache that cannot be read is not worth failing a lookup over; look the rates up again.
    return {};
  }
}

// A grounded answer arrives as prose around the JSON, often fenced, so take the outermost object
// rather than trusting the whole reply to parse.
function extractJSON(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1) throw new Error('No JSON object in the reply');
  return JSON.parse(text.slice(start, end + 1));
}

const rewardsPrompt = (today) => `You look up published credit card earn rates. Today is ${today}.
Search the issuer's own page first, then a reputable card-review site to confirm.
Report only what you find. Never invent a rate, and omit any category you cannot confirm.
A rotating category (Discover-style) must carry the exact quarter it applies to; a rate with no
end date is the card's standing offer. Caps are per the period the issuer states.
Reply with one JSON object and nothing else:
{"card": string, "issuer": string, "rates": [{"category": one of ${JSON.stringify(CATEGORIES)} or null for the catch-all rate,
"percent": number, "startsOn": "YYYY-MM-DD" or null, "endsOn": "YYYY-MM-DD" or null,
"capCents": integer or null, "needsActivation": boolean, "note": short string}], "sources": [url]}
Map each published category onto the closest one in that list: supermarkets to Groceries,
restaurants and dining to Food & drink, gas and transit and flights to Transport, online retail and
department stores to Shopping, utilities and streaming bills to Home & bills, and so on. Points are
counted at one cent each.`;

app.post('/api/card-rewards', async (req, res) => {
  const card = String(req.body?.card || '').trim();
  if (!card) return res.status(400).json({ error: 'A card name is required' });

  const cache = await loadRewards();
  const hit = cache[card.toLowerCase()];
  const freshUntil = hit && new Date(hit.fetchedAt).getTime() + REWARDS_TTL_DAYS * 86400000;
  if (hit && !req.query.refresh && freshUntil > Date.now()) return res.json({ ...hit, cached: true });

  if (!process.env.GEMINI_API_KEY) {
    return res.status(503).json({ error: 'Rewards lookup is not configured. Set GEMINI_API_KEY in backend/.env, or enter the rates by hand.' });
  }

  try {
    const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
    const response = await ai.models.generateContent({
      model: 'gemini-3-flash-preview',
      // Search grounding is what makes this work for a card nobody wrote into the app. The API
      // refuses to mix a search tool with any other, so the JSON shape is asked for in the prompt
      // rather than enforced by a response schema.
      config: {
        tools: [{ googleSearch: {} }],
        systemInstruction: rewardsPrompt(new Date().toISOString().slice(0, 10)),
      },
      contents: `What does the "${card}" card earn, by category, right now?`,
    });

    // An unknown tool key is dropped silently rather than rejected, and the model then answers from
    // memory — which for a rotating quarterly category is confidently wrong data with no warning.
    // Grounding metadata is the proof a search actually happened; without it, refuse the answer.
    const grounded = response.candidates?.[0]?.groundingMetadata;
    if (!grounded?.groundingChunks?.length && !grounded?.webSearchQueries?.length) {
      throw new Error('The model answered without searching, so the rates cannot be trusted');
    }

    const parsed = extractJSON(response.text);
    const entry = { card, fetchedAt: new Date().toISOString(), ...parsed };
    cache[card.toLowerCase()] = entry;
    await writeBlob('rewards', REWARDS_PATH, JSON.stringify(cache, null, 2));
    res.json({ ...entry, cached: false });
  } catch (err) {
    console.error(err.message);
    res.status(502).json({ error: 'Could not look up rates for that card. Enter them by hand, or try again.' });
  }
});

// Forgets every cursor so the next sync replays full history. Needed when the app learns to read
// a field it used to ignore: a cursor reports each change once, so old rows are never re-sent.
app.post('/api/resync', async (req, res) => {
  const items = (await loadItems()).map((item) => ({ ...item, cursor: null }));
  await saveItems(items);
  res.json({ items: items.length });
});

// Left open so the app can tell "nothing is listening" apart from "wrong token", but it
// says nothing about the setup unless the caller proves it belongs here.
app.get('/health', (req, res) => {
  if (!authorized(req)) return res.json({ ok: true });
  res.json({ ok: true, env: PLAID_ENV, authorized: true });
});

const PORT = process.env.PORT || 5100;
app.listen(PORT, () => {
  console.log(`samgloyim backend listening on http://localhost:${PORT} (Plaid env: ${PLAID_ENV})`);
  console.log('');
  console.log('  Access token:  ' + ACCESS_TOKEN);
  console.log('  Paste it into the app under Import \u203a Sync server. Every /api route requires it.');
  console.log('');
});
