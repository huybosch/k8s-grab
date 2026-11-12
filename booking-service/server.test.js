// Phase 23 - test cho booking-service (node:test có sẵn trong Node, không cần thư viện ngoài)
// Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

process.env.PAYMENT_TIMEOUT_MS = "500";
process.env.NOTIFY_TIMEOUT_MS = "300";
const app = require("./server");

let server, base, fakePayment, fakePaymentUrl, fakeNotify, fakeNotifyUrl, notified = [];
let dropNextPayment = 0, paymentBodies = [];

before(async () => {
  // payment-service giả: trả lại đúng body nhận được. dropNextPayment > 0 -> cắt kết nối (giả lập Pod payment vừa tắt)
  fakePayment = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      paymentBodies.push(JSON.parse(body));
      if (dropNextPayment > 0) { dropNextPayment--; return req.socket.destroy(); }
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ service: "payment-service", body: JSON.parse(body) }));
    });
  });
  await new Promise((r) => fakePayment.listen(0, r));
  fakePaymentUrl = `http://127.0.0.1:${fakePayment.address().port}/payment`;

  // notification-service giả: ghi lại body nhận được
  fakeNotify = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      notified.push(JSON.parse(body));
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ service: "notification-service", notificationId: "n-1" }));
    });
  });
  await new Promise((r) => fakeNotify.listen(0, r));
  fakeNotifyUrl = `http://127.0.0.1:${fakeNotify.address().port}/notify`;

  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
  fakePayment.close();
  fakeNotify.close();
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
  process.env.NOTIFICATION_URL = fakeNotifyUrl;
  const r = await postBooking();
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.service, "booking-service");
  assert.equal(body.payment.service, "payment-service");
  assert.deepEqual(body.payment.body, { amount: 100, paymentId: body.bookingId }, "paymentId (idempotency key) = bookingId");
  assert.match(body.bookingId, /^[0-9a-f-]{36}$/, "mỗi booking phải có bookingId (UUID)");
  assert.equal(body.notification.service, "notification-service");
  assert.equal(notified.at(-1).type, "booking-confirmed");
  assert.equal(notified.at(-1).bookingId, body.bookingId);
});

test("payment cắt kết nối lần 1 -> retry CÙNG paymentId -> 200", async () => {
  process.env.PAYMENT_URL = fakePaymentUrl;
  process.env.NOTIFICATION_URL = fakeNotifyUrl;
  paymentBodies = [];
  dropNextPayment = 1;
  const r = await postBooking();
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(paymentBodies.length, 2, "gọi payment đúng 2 lần");
  assert.equal(paymentBodies[0].paymentId, paymentBodies[1].paymentId, "retry phải gửi lại CÙNG paymentId");
  assert.equal(paymentBodies[1].paymentId, body.bookingId);
});

test("notification chết -> booking VẪN 200 (notification = null), không treo", async () => {
  process.env.PAYMENT_URL = fakePaymentUrl;
  process.env.NOTIFICATION_URL = "http://127.0.0.1:1/notify";
  const t0 = Date.now();
  const r = await postBooking();
  assert.equal(r.status, 200);
  assert.equal((await r.json()).notification, null);
  assert.ok(Date.now() - t0 < 1000);
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
  assert.match(text, /http_requests_total\{method="POST",route="\/booking",status="200"\} 3/);
  assert.match(text, /http_requests_total\{method="POST",route="\/booking",status="503"\} 1/);
  assert.doesNotMatch(text, /route="\/health"/, "/health không được tính vào metrics");
});

test("GET /booking/slow?ms=50 trả sau ~50ms (Incident 5)", async () => {
  const t0 = Date.now();
  const r = await fetch(`${base}/booking/slow?ms=50`);
  assert.equal(r.status, 200);
  assert.match(await r.text(), /^done after 0.05s/);
  assert.ok(Date.now() - t0 >= 45);
});
