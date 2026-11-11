// Final Project - test cho notification-service. Chạy: npm test
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
  assert.equal((await fetch(`${base}/health`)).status, 200);
});

test("POST /notify trả notificationId + type", async () => {
  const r = await fetch(`${base}/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ type: "booking-confirmed", bookingId: "b-1" }),
  });
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "notification-service");
  assert.equal(body.type, "booking-confirmed");
  assert.match(body.notificationId, /^[0-9a-f-]{36}$/);
});

test("GET /metrics có counter của /notify", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="POST",route="\/notify",status="200"\} 1/);
});
