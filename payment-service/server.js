const express = require("express");
const { randomUUID } = require("node:crypto");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3004;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

app.post("/payment", (req, res) => {
  console.log("handled by pod:", process.env.HOSTNAME);
  res.json({ service: "payment-service", version: VERSION, transactionId: randomUUID(), body: req.body, pod: process.env.HOSTNAME });
});

// Phase 23: chỉ listen khi chạy trực tiếp; khi test thì require("./server") lấy app
if (require.main === module) {
  app.listen(PORT, () => console.log(`payment-service ${VERSION} listening on ${PORT}`));
}

module.exports = app;
