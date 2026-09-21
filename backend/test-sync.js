// Run: node test-sync.js   (no network, no Plaid — a stub stands in for the bank)
const { syncAll } = require('./sync');

const assert = (ok, what) => {
  if (!ok) { console.error('FAIL:', what); process.exit(1); }
  console.log('ok:', what);
};

const items = [
  { itemId: 'a', institutionName: 'PNC', cursor: 'pnc-1', accessToken: 'x' },
  { itemId: 'b', institutionName: 'Chime', cursor: 'chime-7', accessToken: 'y' },
  { itemId: 'c', institutionName: 'Amex', cursor: 'amex-3', accessToken: 'z' },
];

const loginRequired = Object.assign(new Error('nope'), {
  response: { data: { error_code: 'ITEM_LOGIN_REQUIRED' } },
});

(async () => {
  const result = await syncAll(items, async (item) => {
    if (item.itemId === 'b') throw loginRequired;
    return {
      accounts: [{ accountId: `${item.itemId}-1`, institution: item.institutionName }],
      added: [{ id: `${item.itemId}-t1` }],
      modified: [],
      removed: [],
      cursor: `${item.cursor}-next`,
    };
  }, () => '2026-09-20T18:00:00.000Z');

  assert(result.added.length === 2, 'the two healthy banks still deliver their rows');
  assert(result.accounts.length === 2, 'and their accounts');

  const cursors = Object.fromEntries(result.updated.map((i) => [i.itemId, i.cursor]));
  assert(cursors.a === 'pnc-1-next' && cursors.c === 'amex-3-next', 'healthy banks keep the cursor they reached');
  assert(cursors.b === 'chime-7', 'the failed bank keeps its old cursor rather than losing it');

  const chime = result.status.find((s) => s.itemId === 'b');
  assert(chime.ok === false && chime.needsReauth === true, 'the failure is reported as needing a sign-in');
  assert(result.status.filter((s) => s.ok).length === 2, 'and the others are reported healthy');
  assert(result.updated.find((i) => i.itemId === 'a').lastSyncedAt === '2026-09-20T18:00:00.000Z', 'a good sync is dated');
  assert(result.updated.find((i) => i.itemId === 'b').lastError === 'ITEM_LOGIN_REQUIRED', 'and a bad one remembers why');

  // An ordinary outage is not a sign-in problem, and must not offer that button.
  const flaky = await syncAll([items[0]], async () => { throw new Error('socket hang up'); });
  assert(flaky.status[0].needsReauth === false, 'a network failure is not mistaken for re-auth');
  assert(flaky.status[0].error === 'SYNC_FAILED', 'and is still reported');

  console.log('\nall good');
})();
