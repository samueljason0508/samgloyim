require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');

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
function loadItems() {
  if (!fs.existsSync(STORE_PATH)) return [];
  const raw = fs.readFileSync(STORE_PATH, 'utf8').trim();
  if (!raw) return [];
  return JSON.parse(raw).map((item) => ({ ...item, accessToken: decrypt(item.accessToken) }));
}
function saveItems(items) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const encoded = items.map((item) => ({ ...item, accessToken: encrypt(item.accessToken) }));
  fs.writeFileSync(STORE_PATH, JSON.stringify(encoded, null, 2));
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
    institution: institutionName,
    pending: t.pending,
  };
}

const app = express();
app.use(cors());
app.use(express.json());

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
    const items = loadItems();
    items.push({
      itemId: response.data.item_id,
      accessToken: response.data.access_token,
      institutionName: institution_name || 'Linked bank',
      cursor: null,
      linkedAt: new Date().toISOString(),
    });
    saveItems(items);
    res.json({ item_id: response.data.item_id, institution_name: institution_name || 'Linked bank' });
  } catch (err) {
    console.error(err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to exchange public token' });
  }
});

app.get('/api/items', (req, res) => {
  res.json(loadItems().map(({ itemId, institutionName, linkedAt }) => ({ itemId, institutionName, linkedAt })));
});

app.delete('/api/items/:itemId', async (req, res) => {
  const items = loadItems();
  const target = items.find((i) => i.itemId === req.params.itemId);
  if (!target) return res.status(404).json({ error: 'Not found' });
  try {
    await client.itemRemove({ access_token: target.accessToken });
  } catch (err) {
    console.error(err.response?.data || err.message);
  }
  saveItems(items.filter((i) => i.itemId !== req.params.itemId));
  res.json({ ok: true });
});

app.get('/api/transactions', async (req, res) => {
  try {
    const items = loadItems();
    if (items.length === 0) return res.json({ added: [], modified: [], removed: [] });

    let added = [];
    let modified = [];
    let removed = [];
    const updatedItems = [];

    for (const item of items) {
      let cursor = item.cursor || undefined;
      let hasMore = true;
      while (hasMore) {
        const resp = await client.transactionsSync({ access_token: item.accessToken, cursor });
        added = added.concat(resp.data.added.map((t) => normalize(t, item.institutionName)));
        modified = modified.concat(resp.data.modified.map((t) => normalize(t, item.institutionName)));
        removed = removed.concat(resp.data.removed.map((t) => t.transaction_id));
        cursor = resp.data.next_cursor;
        hasMore = resp.data.has_more;
      }
      updatedItems.push({ ...item, cursor });
    }

    saveItems(updatedItems);
    res.json({ added, modified, removed });
  } catch (err) {
    console.error(err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to sync transactions' });
  }
});

app.get('/health', (req, res) => res.json({ ok: true, env: PLAID_ENV }));

const PORT = process.env.PORT || 5100;
app.listen(PORT, () => console.log(`samgloyim backend listening on http://localhost:${PORT} (Plaid env: ${PLAID_ENV})`));
