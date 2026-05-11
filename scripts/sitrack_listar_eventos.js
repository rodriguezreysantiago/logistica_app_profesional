// Enumera los eventName distintos que devuelve la API de Sitrack
// para inferir qué eventos de conducción podríamos usar para
// calcular un ICM (Índice de Conducción) por chofer.
//
// El poller actual (`sitrackPosicionPoller` en functions/src/index.ts)
// solo persiste posición + odómetro y descarta el campo `eventName`.
// Si Sitrack manda eventos tipo "Frenada brusca", "Aceleración
// brusca", "Exceso de velocidad", etc., podemos:
//   1. Pollearlos y persistirlos en SITRACK_EVENTOS_HISTORICO.
//   2. Agregarlos por chofer/día y calcular un score 0-100.
//   3. Mostrar el ICM en la app igual que el Volvo Score.
//
// Uso (desde la raíz del repo):
//   1. Setear las credenciales como env vars una sola vez:
//      $env:SITRACK_USERNAME = "user"
//      $env:SITRACK_PASSWORD = "pass"
//      (los podés sacar del Secret Manager con
//       `firebase functions:secrets:access SITRACK_USERNAME` y _PASSWORD)
//   2. Correr:
//      node scripts/sitrack_listar_eventos.js
//
// El script:
//   - Hace una llamada GET a /v2/report (mismo endpoint que el poller).
//   - Agrupa por `eventName` y muestra:
//       count por evento, ejemplo de campo `assetName` (patente),
//       un timestamp de muestra.
//   - NO escribe nada en Firestore — es solo análisis.

const SITRACK_BASE = "https://externalappgw.ar.sitrack.com";

const user = process.env.SITRACK_USERNAME;
const pass = process.env.SITRACK_PASSWORD;

if (!user || !pass) {
  console.error(
    "❌ Faltan credenciales. Seteá SITRACK_USERNAME y SITRACK_PASSWORD\n" +
    "   como variables de entorno antes de correr."
  );
  console.error("   En PowerShell:");
  console.error('     $env:SITRACK_USERNAME = "..."');
  console.error('     $env:SITRACK_PASSWORD = "..."');
  console.error(
    "   Las podés sacar del Secret Manager:\n" +
    "     firebase functions:secrets:access SITRACK_USERNAME\n" +
    "     firebase functions:secrets:access SITRACK_PASSWORD"
  );
  process.exit(1);
}

(async () => {
  const authHeader =
    "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");

  console.log(`Llamando ${SITRACK_BASE}/v2/report ...\n`);

  let res;
  try {
    res = await fetch(`${SITRACK_BASE}/v2/report`, {
      method: "GET",
      headers: {
        Authorization: authHeader,
        Accept: "application/json",
      },
    });
  } catch (e) {
    console.error("❌ fetch falló:", e.message);
    process.exit(1);
  }

  if (!res.ok) {
    console.error(`❌ HTTP ${res.status} ${res.statusText}`);
    const body = await res.text().catch(() => "<no body>");
    console.error("Body:", body.substring(0, 500));
    process.exit(1);
  }

  let reports;
  try {
    reports = await res.json();
  } catch (e) {
    console.error("❌ JSON parse falló:", e.message);
    process.exit(1);
  }

  if (!Array.isArray(reports)) {
    console.error("❌ Response no es array. Tipo:", typeof reports);
    console.error("Body:", JSON.stringify(reports).substring(0, 500));
    process.exit(1);
  }

  console.log(`✅ ${reports.length} records recibidos\n`);

  // ─── Agrupar por eventName ───
  const porEvento = new Map();
  for (const r of reports) {
    const evt = (r.eventName || "(sin eventName)").trim();
    if (!porEvento.has(evt)) {
      porEvento.set(evt, {
        count: 0,
        eventId: r.eventId ?? null,
        ejemplos: [],
      });
    }
    const bucket = porEvento.get(evt);
    bucket.count++;
    if (bucket.ejemplos.length < 3) {
      bucket.ejemplos.push({
        asset: r.assetName ?? r.assetId ?? "?",
        date: r.reportDate ?? r.inputDate ?? "?",
        chofer: r.driverName ?? "(sin chofer)",
      });
    }
  }

  // ─── Mostrar ordenado por count desc ───
  console.log("=== EVENTOS DISTINTOS ENCONTRADOS ===\n");
  const sorted = [...porEvento.entries()].sort(
    (a, b) => b[1].count - a[1].count
  );
  for (const [evt, info] of sorted) {
    console.log(`▸ ${evt}  [eventId=${info.eventId}]  (${info.count} reports)`);
    for (const ej of info.ejemplos) {
      console.log(
        `    ${ej.asset.padEnd(15)} ${ej.date.padEnd(28)} ${ej.chofer}`
      );
    }
    console.log("");
  }

  // ─── Análisis ICM ───
  console.log("=== ANÁLISIS PARA ICM ===\n");
  const palabrasClaveICM = [
    "frenad", "brusc", "acelerac", "exces", "veloc",
    "harsh", "braking", "speeding", "overspeed",
    "idle", "idling", "ralenti",
    "curva", "cornering",
    "panic", "alarma",
  ];
  const relevantes = sorted.filter(([evt]) => {
    const low = evt.toLowerCase();
    return palabrasClaveICM.some((kw) => low.includes(kw));
  });

  if (relevantes.length === 0) {
    console.log(
      "❌ Ningún eventName parece de conducción (frenadas, aceleración,\n" +
      "   velocidad, idling). Capaz el `/v2/report` que tenemos\n" +
      "   contratado solo trae eventos de posición + ignición.\n\n" +
      "   Próximo paso: consultar a Sitrack si existe un endpoint\n" +
      "   tipo /v2/events, /v2/alerts o /v2/harsh-events que sí\n" +
      "   exponga eventos de conducción."
    );
  } else {
    console.log("✅ Eventos relevantes para calcular ICM:\n");
    for (const [evt, info] of relevantes) {
      console.log(`   ▸ ${evt}  (${info.count} reports)`);
    }
    console.log(
      "\n   Estos los podemos pollear, persistir en\n" +
      "   SITRACK_EVENTOS_HISTORICO y agregar por chofer/día.\n" +
      "   La fórmula del ICM se calcula con count × peso → 100 - penalización."
    );
  }
})().catch((e) => {
  console.error("error:", e);
  process.exit(1);
});
