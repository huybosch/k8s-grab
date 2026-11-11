const express = require("express");
const { randomUUID } = require("node:crypto");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3005;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

// Final Project: booking (đặt xe xong) và driver (tài xế nhận cuốc) gọi vào đây.
// Chưa gửi SMS/push thật - ghi 1 dòng log JSON (Loki/Alloy thu lại, query được theo type).
app.post("/notify", (req, res) => {
  const notificationId = randomUUID();
  const type = (req.body && req.body.type) || "unknown";
  console.log(JSON.stringify({ event: "notify", notificationId, type, pod: process.env.HOSTNAME, body: req.body }));
  res.json({ service: "notification-service", version: VERSION, notificationId, type });
});

if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`notification-service ${VERSION} listening on ${PORT}`));
  process.on("SIGTERM", () => server.close(() => process.exit(0)));
}

module.exports = app;
