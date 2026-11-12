// Incident 5 - bắn N request chậm CÙNG LÚC, in Pod nào trả lời + thời gian: node ci/slow-burst.js <ms> [n]
const [ms = "15000", n = "30"] = process.argv.slice(2);
const t0 = Date.now();
Promise.all(Array.from({ length: Number(n) }, async (_, i) => {
  try {
    const r = await fetch(`http://127.0.0.1/booking/slow?ms=${ms}`, { signal: AbortSignal.timeout(Number(ms) + 45000) });
    const body = await r.text();
    return { i, status: r.status, pod: (body.match(/by (\S+)/) || [])[1] || body.slice(0, 60), s: (Date.now() - t0) / 1000 };
  } catch (e) {
    return { i, status: "ERR " + ((e.cause && e.cause.code) || e.name), pod: "-", s: (Date.now() - t0) / 1000 };
  }
})).then((rs) => {
  const by = {};
  for (const r of rs) { const k = `${r.status} ${r.pod}`; by[k] = (by[k] || 0) + 1; }
  console.log(JSON.stringify({ ok: rs.filter((r) => r.status === 200).length, fail: rs.filter((r) => r.status !== 200).length, maxSec: Math.max(...rs.map((r) => r.s)), byPod: by }));
});
