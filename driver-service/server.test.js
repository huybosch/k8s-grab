// Final Project - test cho driver-service. Chạy: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

process.env.NOTIFY_TIMEOUT_MS = "300";
const app = require("./server");
let server, base, fakeNotify, received = [];

before(async () => {
  // notification-service giả: ghi lại body nhận được
  fakeNotify = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      received.push(JSON.parse(body));
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ service: "notification-service", notificationId: "n-1" }));
    });
  });
  await new Promise((r) => fakeNotify.listen(0, r));
  server = app.listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server.close(); fakeNotify.close(); });

const accept = (id) =>
  fetch(`${base}/drivers/${id}/accept`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ bookingId: "b-1" }) });

test("GET /drivers trả danh sách tài xế", async () => {
  const body = await (await fetch(`${base}/drivers`)).json();
  assert.equal(body.service, "driver-service");
  assert.ok(body.drivers.includes("driver-1"));
});

test("POST /drivers/:id/accept báo notification-service", async () => {
  process.env.NOTIFICATION_URL = `http://127.0.0.1:${fakeNotify.address().port}/notify`;
  const r = await accept("driver-1");
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.accepted, true);
  assert.equal(body.notification.service, "notification-service");
  assert.deepEqual(received.at(-1), { type: "driver-accepted", driverId: "driver-1", bookingId: "b-1" });
});

test("notification chết -> VẪN nhận cuốc (notification = null), không treo", async () => {
  process.env.NOTIFICATION_URL = "http://127.0.0.1:1/notify";
  const t0 = Date.now();
  const r = await accept("driver-2");
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.accepted, true);
  assert.equal(body.notification, null);
  assert.ok(Date.now() - t0 < 1000);
});

test("tài xế không tồn tại -> 404", async () => {
  assert.equal((await accept("driver-99")).status, 404);
});
