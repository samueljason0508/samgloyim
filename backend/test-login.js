// Run: node test-login.js   (starts the server on a spare port with a throwaway user)
const crypto = require('crypto');
const { spawn } = require('child_process');

const PORT = 5399;
const salt = crypto.randomBytes(16).toString('hex');
const hash = crypto.scryptSync('correct horse', salt, 32).toString('hex');

const server = spawn('node', ['server.js'], {
  cwd: __dirname,
  env: { ...process.env, PORT, BACKEND_ACCESS_TOKEN: 'test-token', BACKEND_USERS: `Tester:${salt}:${hash}` },
  stdio: 'ignore',
});

const post = (body) =>
  fetch(`http://localhost:${PORT}/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const assert = (ok, what) => {
  if (!ok) { server.kill(); console.error('FAIL:', what); process.exit(1); }
  console.log('ok:', what);
};

(async () => {
  for (let i = 0; i < 40; i++) {
    try { await fetch(`http://localhost:${PORT}/health`); break; } catch { await new Promise((r) => setTimeout(r, 250)); }
  }

  const good = await post({ username: 'tester', password: 'correct horse' });
  assert(good.status === 200, 'right password is let in');
  assert((await good.json()).token === 'test-token', 'and is handed the access token');

  assert((await post({ username: 'tester', password: 'wrong' })).status === 401, 'wrong password is refused');
  assert((await post({ username: 'nobody', password: 'correct horse' })).status === 401, 'unknown name is refused');
  assert((await post({})).status === 401, 'an empty body is refused, not crashed on');

  const gated = await fetch(`http://localhost:${PORT}/api/items`);
  assert(gated.status === 401, '/api still needs the token');

  // Guessing has to cost something: the window closes after a handful of wrong tries.
  let last;
  for (let i = 0; i < 10; i++) last = await post({ username: 'tester', password: 'wrong' });
  assert(last.status === 429, 'repeated guessing is throttled');
  assert((await post({ username: 'tester', password: 'correct horse' })).status === 429, 'and the throttle does not spare the right password');

  server.kill();
  console.log('\nall good');
})();
