// Phase 23 (bổ sung): push file này lên main -> cd.yaml chạy trên self-hosted runner -> pipeline deploy driver
const express = require("express");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3002;
const VERSION = process.env.VERSION || "v1";
const NOTIFY_TIMEOUT_MS = Number(process.env.NOTIFY_TIMEOUT_MS || 1000);
const notificationUrl = () => process.env.NOTIFICATION_URL || "http://notification-service/notify";
const DRIVERS = ["driver-1", "driver-2", "driver-3"];

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/drivers", (req, res) => {
  res.json({ service: "driver-service", version: VERSION, drivers: DRIVERS });
});

// Final Project: tài xế nhận cuốc -> báo notification-service.
// Notification là phụ thuộc KHÔNG quan trọng: lỗi/timeout thì vẫn nhận cuốc thành công, chỉ ghi notification = null.
app.post("/drivers/:id/accept", async (req, res) => {
  const driverId = req.params.id;
  if (!DRIVERS.includes(driverId)) return res.status(404).json({ service: "driver-service", error: "driver not found" });
  let notification = null;
  try {
    const r = await fetch(notificationUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "driver-accepted", driverId, bookingId: req.body && req.body.bookingId }),
      signal: AbortSignal.timeout(NOTIFY_TIMEOUT_MS),
    });
    if (!r.ok) throw new Error(`notification-service HTTP ${r.status}`);
    notification = await r.json();
  } catch (err) {
    console.error("notify failed:", err.name === "TimeoutError" ? `timeout ${NOTIFY_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message);
  }
  res.json({ service: "driver-service", version: VERSION, driverId, accepted: true, notification });
});

if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`driver-service ${VERSION} listening on ${PORT}`));
  // nginx giữ kết nối upstream 60s; Node mặc định đóng kết nối rảnh sau 5s -> race: nginx gửi request vào kết nối Node vừa đóng
  // -> 502 'upstream prematurely closed' (gặp 1 lần ở Incident 7, POST không được retry). Server phải giữ LÂU HƠN proxy.
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  process.on("SIGTERM", () => server.close(() => process.exit(0)));
}

module.exports = app;
