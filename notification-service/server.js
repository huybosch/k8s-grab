const express = require("express");
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3005;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

app.post("/notify", (req, res) => {
  res.json({ service: "notification-service", version: VERSION, body: req.body });
});

app.listen(PORT, () => console.log(`notification-service ${VERSION} listening on ${PORT}`));
