const express = require("express");
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3002;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/drivers", (req, res) => {
  res.json({ service: "driver-service", version: VERSION, drivers: ["driver-1", "driver-2"] });
});

app.listen(PORT, () => console.log(`driver-service ${VERSION} listening on ${PORT}`));
