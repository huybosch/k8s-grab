// Phase 23 + Final Project - test cho payment-service (DB giả, không cần PostgreSQL). Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");

const app = require("./server");
let server, base, rows = [], dbDown = false;

before(async () => {
  // DB giả: ghi nhớ các INSERT, mô phỏng được DB chết
  app.set("db", {
    query: async (sql, params) => {
      if (dbDown) throw Object.assign(new Error("connect ECONNREFUSED"), { code: "ECONNREFUSED" });
      if (sql.startsWith("INSERT")) { rows.push(params); return { rows: [] }; }
      return { rows: [{ count: rows.length, total: rows.reduce((s, r) => s + r[1], 0) }] };
    },
  });
  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const pay = (body) =>
  fetch(`${base}/payment`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

test("GET /health trả 200", async () => {
  const r = await fetch(`${base}/health`);
  assert.equal(r.status, 200);
});

test("POST /payment ghi 1 dòng vào DB và trả transactionId", async () => {
  const r = await pay({ amount: 42 });
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "payment-service");
  assert.deepEqual(body.body, { amount: 42 });
  assert.match(body.transactionId, /^[0-9a-f-]{36}$/, "mỗi payment phải có transactionId (UUID)");
  assert.deepEqual(rows.at(-1), [body.transactionId, 42]);
});

test("amount không hợp lệ -> 400, không ghi DB", async () => {
  const n = rows.length;
  assert.equal((await pay({ amount: -5 })).status, 400);
  assert.equal((await pay({ amount: "abc" })).status, 400);
  assert.equal(rows.length, n);
});

test("DB chết -> 503 database unavailable, /health vẫn 200", async () => {
  dbDown = true;
  try {
    const r = await pay({ amount: 1 });
    assert.equal(r.status, 503);
    assert.equal((await r.json()).error, "database unavailable");
    assert.equal((await fetch(`${base}/health`)).status, 200);
  } finally { dbDown = false; }
});

test("GET /payments/stats đếm từ DB", async () => {
  const body = await (await fetch(`${base}/payments/stats`)).json();
  assert.equal(body.count, rows.length);
});

test("GET /metrics có counter của /payment", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="POST",route="\/payment",status="200"\} 1/);
  assert.match(text, /http_requests_total\{method="POST",route="\/payment",status="503"\} 1/);
});
