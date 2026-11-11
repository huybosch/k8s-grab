// Phase 23 + Final Project - test cho user-service (Redis giả). Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");

process.env.REDIS_TIMEOUT_MS = "200";
const app = require("./server");
let server, base, counter = 0, mode = "ok";

before(async () => {
  // Redis giả: "ok" đếm tăng dần, "down" lỗi ngay (disableOfflineQueue), "hang" không bao giờ trả lời
  app.set("redis", {
    incr: () => (mode === "ok" ? Promise.resolve(++counter)
      : mode === "down" ? Promise.reject(new Error("The client is closed"))
      : new Promise(() => {})),
  });
  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const getUsers = async () => (await fetch(`${base}/users`)).json();

test("GET /health trả 200", async () => {
  const r = await fetch(`${base}/health`);
  assert.equal(r.status, 200);
});

test("GET /users trả danh sách user + views đếm bằng Redis", async () => {
  mode = "ok";
  const a = await getUsers();
  const b = await getUsers();
  assert.equal(a.service, "user-service");
  assert.ok(Array.isArray(a.users) && a.users.length > 0);
  assert.equal(b.views, a.views + 1);
});

test("Redis chết -> /users VẪN 200, views = null", async () => {
  mode = "down";
  const r = await fetch(`${base}/users`);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).views, null);
});

test("Redis treo -> /users trả trong ~timeout, không treo theo", async () => {
  mode = "hang";
  const t0 = Date.now();
  const body = await getUsers();
  assert.equal(body.views, null);
  assert.ok(Date.now() - t0 < 1000);
});

test("GET /metrics có counter của /users", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="GET",route="\/users",status="200"\} 4/);
});
