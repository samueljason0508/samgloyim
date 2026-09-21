// Syncing many banks at once, without letting one of them speak for the rest.
//
// A bank that wants you to sign in again throws, and a loop that wraps every item in one `try`
// turns that into: no rows for anyone, and every other bank's cursor thrown away with it. With
// six linked banks that is the difference between "Chime needs re-authenticating" and "the app
// stopped importing and nobody knows why". So each bank is synced on its own, its failure is
// recorded rather than raised, and the ones that worked keep what they earned.
async function syncAll(items, syncOne, now = () => new Date().toISOString()) {
  const accounts = [];
  const added = [];
  const modified = [];
  const removed = [];
  const status = [];
  const updated = [];

  for (const item of items) {
    const at = now();
    try {
      const result = await syncOne(item);
      for (const account of result.accounts || []) {
        if (!accounts.some((existing) => existing.accountId === account.accountId)) accounts.push(account);
      }
      added.push(...(result.added || []));
      modified.push(...(result.modified || []));
      removed.push(...(result.removed || []));
      updated.push({ ...item, cursor: result.cursor, lastSyncedAt: at, lastError: null });
      status.push({ itemId: item.itemId, institutionName: item.institutionName, ok: true, lastSyncedAt: at });
    } catch (err) {
      // The cursor stays where it was: resuming from the last complete sync costs one extra
      // page and cannot lose a transaction, which a guessed-forward cursor could.
      const code = err?.response?.data?.error_code || err?.error_code || null;
      updated.push({ ...item, lastError: code || 'SYNC_FAILED' });
      status.push({
        itemId: item.itemId,
        institutionName: item.institutionName,
        ok: false,
        // The one failure the user can actually fix, and the only one worth a button.
        needsReauth: code === 'ITEM_LOGIN_REQUIRED',
        error: code || 'SYNC_FAILED',
        lastSyncedAt: item.lastSyncedAt || null,
      });
    }
  }

  return { accounts, added, modified, removed, status, updated };
}

module.exports = { syncAll };
