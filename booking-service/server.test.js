// Phase 23 - test cho booking-service (node:test có sẵn trong Node, không cần thư viện ngoài)
// Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

process.env.PAYMENT_TIMEOUT_MS = "500";
const app = require("./server");

let server, base, fakePayment, fakePaymentUrl;

before(async () => {
  // payment-service giả: trả lại đúng body nhận được
  fakePayment = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ service: "payment-service", body: JSON.parse(body) }));
    });
  });
  await new Promise((r) => fakePayment.listen(0, r));
  fakePaymentUrl = `http://127.0.0.1:${fakePayment.address().port}/payment`;

  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
  fakePayment.close();
});

const postBooking = () =>
  fetch(`${base}/booking`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });

test("GET /health trả 200", async () => {
  const r = await fetch(`${base}/health`);
  assert.equal(r.status, 200);
  assert.equal(await r.text(), "ok");
});

test("POST /booking gọi payment và trả kết quả của payment", async () => {
  process.env.PAYMENT_URL = fakePaymentUrl;
  const r = await postBooking();
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "booking-service");
  assert.equal(body.payment.service, "payment-service");
  assert.deepEqual(body.payment.body, { amount: 100 });
});

test("POST /booking trả 503 (không treo) khi payment không kết nối được", async () => {
  process.env.PAYMENT_URL = "http://127.0.0.1:1/payment"; // port 1: không có gì lắng nghe
  const t0 = Date.now();
  const r = await postBooking();
  assert.equal(r.status, 503);
  assert.equal((await r.json()).error, "payment unavailable");
  assert.ok(Date.now() - t0 < 2000, "phải lỗi nhanh, không được treo");
});

test("GET /metrics có counter http_requests_total theo route + status", async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="POST",route="\/booking",status="200"\} 1/);
  assert.match(text, /http_requests_total\{method="POST",route="\/booking",status="503"\} 1/);
  assert.doesNotMatch(text, /route="\/health"/, "/health không được tính vào metrics");
});
