const express = require("express");
const metrics = require("./metrics");
const app = express();
app.use(express.json());
app.use(metrics.middleware);
metrics.mount(app);

const PORT = process.env.PORT || 3001;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/users", (req, res) => {
  res.json({ service: "user-service", version: VERSION, users: ["alice", "bob"] });
});

// Phase 23: chỉ listen khi chạy trực tiếp; khi test thì require("./server") lấy app
if (require.main === module) {
  app.listen(PORT, () => console.log(`user-service ${VERSION} listening on ${PORT}`));
}

module.exports = app;
