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

// Incident 6 - FAULT INJECTION cho lab (giống BUGGY của booking): giả lập memory leak kiểu "cache không giới hạn".
// > 0 -> mỗi request /users giữ lại N KB, không bao giờ giải phóng. Mặc định 0 = tắt.
const LEAK_KB = Number(process.env.LEAK_KB_PER_REQUEST || 0);
const leaked = [];

const withTimeout = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`timeout ${ms}ms`)), ms))]);

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/users", async (req, res) => {
  if (LEAK_KB > 0) leaked.push(Buffer.alloc(LEAK_KB * 1024, 1)); // fill = chạm vào từng trang nhớ -> tính vào RSS thật
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
