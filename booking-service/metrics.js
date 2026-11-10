// Phase 21 - Prometheus metrics (dùng chung cho booking / payment / user - mỗi service 1 bản copy)
const client = require("prom-client");

client.collectDefaultMetrics(); // CPU, memory, event loop lag, GC... của process Node.js

const labelNames = ["method", "route", "status"];
const httpRequests = new client.Counter({
  name: "http_requests_total",
  help: "Tổng số HTTP request đã xử lý",
  labelNames,
});
const httpDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Thời gian xử lý HTTP request (giây)",
  labelNames,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
});

// Bỏ qua /metrics và /health để probe + scrape không làm nhiễu số liệu
const SKIP = new Set(["/metrics", "/health"]);

function middleware(req, res, next) {
  if (SKIP.has(req.path)) return next();
  const end = httpDuration.startTimer();
  let recorded = false;
  const record = (status) => {
    if (recorded) return;
    recorded = true;
    // dùng route pattern (vd. "/booking") thay vì URL thật -> tránh bùng nổ cardinality
    const labels = { method: req.method, route: req.route ? req.route.path : "unmatched", status };
    httpRequests.inc(labels);
    end(labels);
  };
  res.on("finish", () => record(String(res.statusCode)));
  // Client bỏ cuộc (timeout/huỷ) TRƯỚC khi server trả lời -> "finish" KHÔNG bao giờ chạy.
  // Không bắt "close" thì những request này biến mất khỏi metrics. 499 = quy ước của nginx.
  res.on("close", () => { if (!res.writableFinished) record("499"); });
  next();
}

function mount(app) {
  app.get("/metrics", async (req, res) => {
    res.set("Content-Type", client.register.contentType);
    res.end(await client.register.metrics());
  });
}

module.exports = { middleware, mount };
