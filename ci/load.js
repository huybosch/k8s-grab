// Production Simulation - tải song song (Node 18+, không cần thư viện): node ci/load.js <url> <concurrency> <seconds> [method]
// In mỗi giây: số request OK / lỗi / p95 (ms); cuối cùng in tổng + mẫu lỗi.
const [url, conc = "20", secs = "30", method = "POST"] = process.argv.slice(2);
const end = Date.now() + Number(secs) * 1000;
const t0 = Date.now();
let ok = 0, fail = 0, sec = { ok: 0, fail: 0, lat: [] };
const errors = new Map();
const tick = setInterval(() => {
  sec.lat.sort((a, b) => a - b);
  const p95 = sec.lat.length ? sec.lat[Math.floor(sec.lat.length * 0.95)] : 0;
  console.log(`+${String(Math.round((Date.now() - t0) / 1000)).padStart(3)}s ok=${sec.ok} fail=${sec.fail} p95=${p95}ms`);
  sec = { ok: 0, fail: 0, lat: [] };
}, 1000);
async function worker() {
  while (Date.now() < end) {
    const s = Date.now();
    try {
      const r = await fetch(url, { method, headers: { "Content-Type": "application/json" }, body: method === "GET" ? undefined : "{}", signal: AbortSignal.timeout(10000) });
      await r.arrayBuffer();
      if (r.status >= 500) throw new Error(`HTTP ${r.status}`);
      ok++; sec.ok++;
    } catch (e) {
      fail++; sec.fail++;
      const k = e.name === "TimeoutError" ? "timeout 10s" : (e.cause && e.cause.code) || e.message;
      errors.set(k, (errors.get(k) || 0) + 1);
    }
    sec.lat.push(Date.now() - s);
  }
}
Promise.all(Array.from({ length: Number(conc) }, worker)).then(() => {
  clearInterval(tick);
  console.log(`TOTAL ok=${ok} fail=${fail}`, errors.size ? JSON.stringify(Object.fromEntries(errors)) : "");
});
