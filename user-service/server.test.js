// Phase 23 - test cho user-service. Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");

const app = require("./server");
let server, base;

before(async () => {
  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

test("GET /health trả 200", async () => {
  const r = await fetch(`${base}/health`);
  assert.equal(r.status, 200);
});

test("GET /users trả danh sách user", async () => {
  const r = await fetch(`${base}/users`);
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "user-service");
  assert.ok(Array.isArray(body.users) && body.users.length > 0);
});

test("GET /metrics có counter của /users", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="GET",route="\/users",status="200"\} 1/);
});
