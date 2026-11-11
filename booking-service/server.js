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
const PAYMENT_TIMEOUT_MS = Number(process.env.PAYMENT_TIMEOUT_MS || 2000);
// Phase 23: đọc mỗi request (không phải lúc load) để test trỏ được sang payment giả
const paymentUrl = () => process.env.PAYMENT_URL || "http://payment-service/payment";
const NOTIFY_TIMEOUT_MS = Number(process.env.NOTIFY_TIMEOUT_MS || 1000);
const notificationUrl = () => process.env.NOTIFICATION_URL || "http://notification-service/notify";

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

  try {
    const r = await fetch(paymentUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount: 100 }),
      // Phase 21: không có timeout -> undici chờ 10s rồi mới lỗi, client đã bỏ đi từ trước
      signal: AbortSignal.timeout(PAYMENT_TIMEOUT_MS),
    });
    if (!r.ok) throw new Error(`payment-service HTTP ${r.status}`);
    const payment = await r.json();
    const bookingId = randomUUID();
    const notification = await notify({ type: "booking-confirmed", bookingId, transactionId: payment.transactionId });
    res.json({ service: "booking-service", version: VERSION, bookingId, payment, notification });
  } catch (err) {
    const detail = err.name === "TimeoutError" ? `timeout ${PAYMENT_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message;
    console.error("payment call failed:", detail);
    res.status(503).json({ service: "booking-service", version: VERSION, error: "payment unavailable", detail });
  }
});

app.get("/slow", (req, res) => {
  setTimeout(() => res.send("done after 10s"), 10000);
});

// Phase 23: chỉ listen khi chạy trực tiếp (node server.js); khi test thì require("./server") lấy app
if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`booking-service ${VERSION} listening on ${PORT}`));

  process.on("SIGTERM", () => {
    console.log("SIGTERM received, stop accepting new requests, finish in-flight ones");
    server.close(() => {
      console.log("All connections closed, exiting");
      process.exit(0);
    });
  });
}

module.exports = app;
