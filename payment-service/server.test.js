// Phase 23 - test cho payment-service. Chạy: npm test
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

test("POST /payment trả lại body đã nhận", async () => {
  const r = await fetch(`${base}/payment`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount: 42 }),
  });
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "payment-service");
  assert.deepEqual(body.body, { amount: 42 });
  assert.match(body.transactionId, /^[0-9a-f-]{36}$/, "mỗi payment phải có transactionId (UUID)");
});

test("GET /metrics có counter của /payment", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="POST",route="\/payment",status="200"\} 1/);
});
