const express = require("express");
const { createClient } = require("redis");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3001;
const VERSION = process.env.VERSION || "v1";
const REDIS_TIMEOUT_MS = Number(process.env.REDIS_TIMEOUT_MS || 300);

// Final Project: Redis = cache/counter, KHÔNG phải nguồn dữ liệu chính.
// Redis chết -> /users vẫn trả danh sách user, chỉ thiếu "views" (null). Không có REDIS_URL (test, local) -> bỏ qua Redis.
function createRedis(url) {
  const client = createClient({
    url,
    disableOfflineQueue: true, // mất kết nối -> lệnh lỗi NGAY, không xếp hàng chờ (request không bị treo)
    socket: { connectTimeout: 1000, reconnectStrategy: (retries) => Math.min(retries * 200, 2000) },
  });
  let lastError = "";
  client.on("error", (err) => { if (err.message !== lastError) console.error("redis error:", (lastError = err.message)); });
  client.on("ready", () => { lastError = ""; console.log("redis ready"); });
  client.connect().catch(() => {}); // lỗi kết nối lần đầu: reconnectStrategy tự thử lại
  return client;
}
app.set("redis", process.env.REDIS_URL && require.main === module ? createRedis(process.env.REDIS_URL) : null);

const withTimeout = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`timeout ${ms}ms`)), ms))]);

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/users", async (req, res) => {
  let views = null;
  const redis = app.get("redis");
  if (redis) {
    try { views = await withTimeout(redis.incr("users:views"), REDIS_TIMEOUT_MS); }
    catch (err) { /* cache lỗi không làm hỏng request */ }
  }
  res.json({ service: "user-service", version: VERSION, users: ["alice", "bob"], views });
});

// Phase 23: chỉ listen khi chạy trực tiếp; khi test thì require("./server") lấy app
if (require.main === module) {
  const server = app.listen(PORT, () => console.log(`user-service ${VERSION} listening on ${PORT}`));
  process.on("SIGTERM", () => server.close(() => process.exit(0)));
}

module.exports = app;
