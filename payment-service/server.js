const express = require("express");
const { randomUUID } = require("node:crypto");
const { Pool } = require("pg");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3004;
const VERSION = process.env.VERSION || "v1";

// Final Project: payment ghi vào PostgreSQL (bảng payments - tạo bởi Job db-init của chart grab-platform).
// User DB riêng "payment" (chỉ SELECT + INSERT), KHÔNG dùng superuser postgres.
// Timeout ngắn: DB chậm/chết -> trả 503 sau ~2s thay vì treo (booking chờ payment tối đa 2s).
function createDb() {
  const pool = new Pool({
    host: process.env.DB_HOST || "postgres",
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || "grabmini",
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    max: 5,
    connectionTimeoutMillis: 1500,
    query_timeout: 1500,
  });
  // client rảnh bị DB ngắt (vd. postgres restart) -> pool phát "error"; không bắt thì process crash
  pool.on("error", (err) => console.error("pg pool error:", err.message));
  return pool;
}
// test thay bằng DB giả: app.set("db", { query: async () => ... })
app.set("db", null);
const db = () => app.get("db") || app.set("db", createDb()).get("db");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

app.get("/health", (req, res) => res.status(200).send("ok"));
// /health KHÔNG kiểm tra DB: DB chết mà liveness fail -> kubelet restart toàn bộ Pod payment vô ích (DB vẫn chết)

app.post("/payment", async (req, res) => {
  const amount = Number((req.body && req.body.amount) ?? 0);
  if (!Number.isFinite(amount) || amount < 0) {
    return res.status(400).json({ service: "payment-service", error: "invalid amount" });
  }
  // Idempotency key: caller (booking) gửi paymentId -> gọi lại (retry) cùng paymentId KHÔNG ghi trừ tiền 2 lần.
  // Không gửi -> tự sinh (mỗi lần gọi = 1 payment mới).
  const paymentId = req.body && req.body.paymentId;
  if (paymentId !== undefined && !UUID.test(String(paymentId))) {
    return res.status(400).json({ service: "payment-service", error: "invalid paymentId" });
  }
  const transactionId = paymentId || randomUUID();
  try {
    await db().query("INSERT INTO payments (id, amount) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING", [transactionId, amount]);
  } catch (err) {
    console.error("payment insert failed:", err.code || err.message);
    return res.status(503).json({ service: "payment-service", version: VERSION, error: "database unavailable" });
  }
  console.log("handled by pod:", process.env.HOSTNAME);
  res.json({ service: "payment-service", version: VERSION, transactionId, body: req.body, pod: process.env.HOSTNAME });
});

app.get("/payments/stats", async (req, res) => {
  try {
    const { rows } = await db().query("SELECT count(*)::int AS count, coalesce(sum(amount), 0)::float AS total FROM payments");
    res.json({ service: "payment-service", ...rows[0] });
  } catch (err) {
    res.status(503).json({ service: "payment-service", error: "database unavailable" });
  }
});

if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`payment-service ${VERSION} listening on ${PORT}`));
  process.on("SIGTERM", () => server.close(() => db().end().finally(() => process.exit(0))));
}

module.exports = app;
