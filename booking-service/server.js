// demo deploy 2026-11-14 00:28:42
const express = require("express");
const { randomUUID } = require("node:crypto");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3003;
const VERSION = process.env.VERSION || "v1";
const BUGGY = process.env.BUGGY === "true";
// Final Project: tối đa 2 lần × 1s (trước đây 1 lần × 2s) -> tổng thời gian chờ payment gần như không đổi
const PAYMENT_TIMEOUT_MS = Number(process.env.PAYMENT_TIMEOUT_MS || 1000);
const PAYMENT_ATTEMPTS = Number(process.env.PAYMENT_ATTEMPTS || 2);
// Phase 23: đọc mỗi request (không phải lúc load) để test trỏ được sang payment giả
const paymentUrl = () => process.env.PAYMENT_URL || "http://payment-service/payment";
const NOTIFY_TIMEOUT_MS = Number(process.env.NOTIFY_TIMEOUT_MS || 1000);
const notificationUrl = () => process.env.NOTIFICATION_URL || "http://notification-service/notify";

// Final Project: gọi payment, RETRY khi lỗi kết nối / timeout / 5xx.
// Retry 1 POST trừ tiền chỉ an toàn vì có idempotency key: paymentId = bookingId -> payment ghi ON CONFLICT DO NOTHING,
// lần 1 thực ra đã ghi (chỉ mất response) thì lần 2 không ghi thêm.
// Vì sao cần: lúc rollout, kết nối có thể tới Pod payment vừa tắt (kube-proxy cập nhật iptables trễ) -> ECONNREFUSED / treo.
async function callPayment(paymentId) {
  for (let attempt = 1; ; attempt++) {
    try {
      const r = await fetch(paymentUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ amount: 100, paymentId }),
        // Phase 21: không có timeout -> undici chờ 10s rồi mới lỗi, client đã bỏ đi từ trước
        signal: AbortSignal.timeout(PAYMENT_TIMEOUT_MS),
      });
      if (r.status >= 500) throw new Error(`payment-service HTTP ${r.status}`);
      if (!r.ok) throw Object.assign(new Error(`payment-service HTTP ${r.status}`), { noRetry: true }); // 4xx: gọi lại vẫn sai
      return await r.json();
    } catch (err) {
      const detail = err.name === "TimeoutError" ? `timeout ${PAYMENT_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message;
      if (err.noRetry || attempt >= PAYMENT_ATTEMPTS) throw Object.assign(err, { detail });
      console.error(`payment attempt ${attempt} failed (${detail}) -> retry`);
      await new Promise((r) => setTimeout(r, 50));
    }
  }
}

// Final Project: báo notification-service. Phụ thuộc KHÔNG quan trọng (khác payment):
// lỗi/timeout -> trả null, booking vẫn thành công. Timeout ngắn hơn payment để không kéo dài request.
async function notify(payload) {
  try {
    const r = await fetch(notificationUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(NOTIFY_TIMEOUT_MS),
    });
    if (!r.ok) throw new Error(`notification-service HTTP ${r.status}`);
    return await r.json();
  } catch (err) {
    console.error("notify failed:", err.name === "TimeoutError" ? `timeout ${NOTIFY_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message);
    return null;
  }
}

let healthy = true;
app.get("/health", (req, res) => res.status(healthy ? 200 : 500).send(healthy ? "ok" : "fail"));
app.post("/toggle-health", (req, res) => { healthy = !healthy; res.json({ healthy }); });

app.post("/booking", async (req, res) => {
  if (BUGGY) {
    return res.status(500).json({ service: "booking-service", version: VERSION, error: "internal error" });
  }

  const bookingId = randomUUID();
  try {
    const payment = await callPayment(bookingId);
    const notification = await notify({ type: "booking-confirmed", bookingId, transactionId: payment.transactionId });
    res.json({ service: "booking-service", version: VERSION, bookingId, payment, notification });
  } catch (err) {
    const detail = err.name === "TimeoutError" ? `timeout ${PAYMENT_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message;
    console.error("payment call failed:", detail);
    res.status(503).json({ service: "booking-service", version: VERSION, error: "payment unavailable", detail });
  }
});

// Phase 12 + Incident 5: request chậm giả lập (mặc định 10s, ?ms=15000 -> 15s, tối đa 60s)
// /booking/slow: đi qua được Ingress (prefix /booking) + NetworkPolicy (chỉ ingress-nginx vào được booking)
app.get(["/slow", "/booking/slow"], (req, res) => {
  const ms = Math.min(Number(req.query.ms) || 10000, 60000);
  setTimeout(() => res.send(`done after ${ms / 1000}s by ${process.env.HOSTNAME}`), ms);
});

// Phase 23: chỉ listen khi chạy trực tiếp (node server.js); khi test thì require("./server") lấy app
if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`booking-service ${VERSION} listening on ${PORT}`));
  // nginx giữ kết nối upstream 60s; Node mặc định đóng kết nối rảnh sau 5s -> race: nginx gửi request vào kết nối Node vừa đóng
  // -> 502 'upstream prematurely closed' (gặp 1 lần ở Incident 7, POST không được retry). Server phải giữ LÂU HƠN proxy.
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;

  process.on("SIGTERM", () => {
    console.log("SIGTERM received, stop accepting new requests, finish in-flight ones");
    server.close(() => {
      console.log("All connections closed, exiting");
      process.exit(0);
    });
  });
}

module.exports = app;
