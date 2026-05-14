// Probe específico para verificar si el bloque `uptimeData` viene
// en el response de /vehicle/vehiclestatuses para un VIN dado.
//
// Contexto: Vecchi le pidió a Volvo activar el bloque UPTIME (que
// trae serviceDistance + tellTaleInfo + engineCoolantTemperature +
// etc., crítico para mantenimiento preventivo). Volvo respondió
// pidiendo probar con un chasis específico — este script automatiza
// la prueba para cualquier VIN y reporta el contenido completo.
//
// USO (PowerShell, sin exponer credenciales en history):
//
//   cd "C:\Users\Colo Logistica\coopertrans_movil"
//   $cred = Get-Credential -Message "Volvo Connect" -UserName "018B1E992E"
//   $env:VOLVO_USERNAME = $cred.UserName
//   $env:VOLVO_PASSWORD = $cred.GetNetworkCredential().Password
//   node scripts/probar_volvo_uptime_data.js 9BVRG10C2TE626557
//   Remove-Item Env:VOLVO_USERNAME, Env:VOLVO_PASSWORD
//
// El argumento es el VIN a probar. Si no se pasa, default al VIN
// que sugirió el soporte de Volvo en el mail del 2026-05-XX
// (`9BVRG10C2TE626557` patente AH628EW).
//
// Diagnóstico:
//   ✅ uptimeData con keys → ACTIVADO. Reportar a Volvo confirmando.
//   ❌ uptimeData ausente o vacío → NO activado para esa unidad.
//      Mandar el output crudo a Volvo para que escalen.

const username = process.env.VOLVO_USERNAME;
const password = process.env.VOLVO_PASSWORD;
const base = process.env.VOLVO_BASE || 'https://api.volvotrucks.com';

if (!username || !password) {
  console.error('❌ Faltan VOLVO_USERNAME o VOLVO_PASSWORD en el environment.');
  console.error('   Ver bloque USO en el header del script.');
  process.exit(1);
}

const vin = (process.argv[2] || '9BVRG10C2TE626557').trim().toUpperCase();
if (!/^[A-Z0-9]{17}$/.test(vin)) {
  console.error(`❌ VIN inválido: "${vin}". Debe ser 17 caracteres alfanuméricos.`);
  process.exit(1);
}

const auth = 'Basic ' + Buffer.from(`${username}:${password}`).toString('base64');

(async () => {
  // Pedimos los 3 contentFilter relevantes + el additionalContent
  // VOLVOGROUPSNAPSHOT que es el que trae serviceDistance dentro de
  // snapshotData.volvoGroupSnapshot (cuando uptimeData no está).
  const url = `${base}/vehicle/vehiclestatuses?` +
    `vin=${encodeURIComponent(vin)}` +
    `&latestOnly=true` +
    `&contentFilter=ACCUMULATED,SNAPSHOT,UPTIME` +
    `&additionalContent=VOLVOGROUPSNAPSHOT`;

  console.log('Volvo /vehicle/vehiclestatuses uptimeData probe');
  console.log(`Base : ${base}`);
  console.log(`VIN  : ${vin}`);
  console.log(`User : ${username}  (password leída del env, no se imprime)`);
  console.log(`Hora : ${new Date().toLocaleString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires' })} ART`);
  console.log('─'.repeat(70));
  console.log(`GET ${url}`);
  console.log('─'.repeat(70));

  const t0 = Date.now();
  let res;
  try {
    res = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: auth,
        Accept: 'application/x.volvogroup.com.vehiclestatuses.v1.0+json; UTF-8',
      },
    });
  } catch (e) {
    console.error(`❌ Error de red: ${e.message}`);
    process.exit(1);
  }
  const t1 = Date.now();

  console.log(`HTTP ${res.status} ${res.statusText}  (latencia ${t1 - t0}ms)`);
  const ct = res.headers.get('content-type');
  if (ct) console.log(`content-type : ${ct}`);

  let body = '';
  try { body = await res.text(); } catch { /* ignore */ }

  if (!res.ok) {
    console.log(`❌ HTTP error. Body (primeros 1500 chars):`);
    console.log(body.slice(0, 1500));
    process.exit(1);
  }

  let data;
  try {
    data = JSON.parse(body);
  } catch (e) {
    console.log(`⚠ No pude parsear JSON: ${e.message}`);
    console.log('Body crudo:');
    console.log(body.slice(0, 2000));
    process.exit(1);
  }

  // Estructura esperada: vehicleStatusResponse.vehicleStatuses[0].
  // Cada vehicleStatus tiene snapshotData / accumulatedData / uptimeData.
  const list = data?.vehicleStatusResponse?.vehicleStatuses;
  if (!Array.isArray(list) || list.length === 0) {
    console.log('⚠ La response no tiene vehicleStatuses[]. Cuerpo completo:');
    console.log(JSON.stringify(data, null, 2).slice(0, 3000));
    process.exit(1);
  }

  console.log('');
  console.log(`✓ Recibí ${list.length} vehicleStatus(es).`);
  console.log('');

  for (let i = 0; i < list.length; i++) {
    const vs = list[i];
    console.log('═'.repeat(70));
    console.log(`vehicleStatus[${i}]`);
    console.log('═'.repeat(70));

    // Top level info — útil para confirmar que es la patente correcta.
    console.log(`  vin                   : ${vs.vin || '(sin vin)'}`);
    console.log(`  vehicleId             : ${vs.vehicleId || '(sin id)'}`);
    if (vs.hrTotalVehicleDistance != null) {
      console.log(`  hrTotalVehicleDistance: ${vs.hrTotalVehicleDistance}`);
    }
    if (vs.totalEngineHours != null) {
      console.log(`  totalEngineHours      : ${vs.totalEngineHours}`);
    }
    if (vs.engineTotalFuelUsed != null) {
      console.log(`  engineTotalFuelUsed   : ${vs.engineTotalFuelUsed}`);
    }

    // ─── snapshotData ─────────────────────────────────────────
    if (vs.snapshotData) {
      console.log('');
      console.log('  📦 snapshotData presente:');
      console.log(`     keys: ${Object.keys(vs.snapshotData).join(', ')}`);
      const vgs = vs.snapshotData.volvoGroupSnapshot;
      if (vgs) {
        console.log('     ✓ volvoGroupSnapshot presente:');
        if (vgs.serviceDistance != null) {
          console.log(`        serviceDistance: ${vgs.serviceDistance}`);
        } else {
          console.log('        (sin serviceDistance dentro de volvoGroupSnapshot)');
        }
        const otrasKeys = Object.keys(vgs).filter((k) => k !== 'serviceDistance');
        if (otrasKeys.length > 0) {
          console.log(`        otras keys: ${otrasKeys.join(', ')}`);
        }
      }
    }

    // ─── accumulatedData ──────────────────────────────────────
    if (vs.accumulatedData) {
      console.log('');
      console.log('  📦 accumulatedData presente:');
      console.log(`     keys: ${Object.keys(vs.accumulatedData).join(', ')}`);
    }

    // ─── uptimeData — LO QUE NOS INTERESA ─────────────────────
    console.log('');
    if (vs.uptimeData) {
      console.log('  🟢 uptimeData PRESENTE — ¡activado para esta unidad!');
      console.log(`     keys: ${Object.keys(vs.uptimeData).join(', ')}`);
      console.log('');
      console.log('     Contenido completo:');
      const dump = JSON.stringify(vs.uptimeData, null, 2);
      console.log(dump.split('\n').map((l) => '       ' + l).join('\n'));

      // Highlights de los campos críticos para mantenimiento.
      if (vs.uptimeData.serviceDistance != null) {
        console.log('');
        console.log(`     ⭐ serviceDistance = ${vs.uptimeData.serviceDistance}`);
      }
      if (vs.uptimeData.tellTaleInfo != null) {
        const tt = vs.uptimeData.tellTaleInfo;
        const len = Array.isArray(tt) ? tt.length : Object.keys(tt).length;
        console.log(`     ⭐ tellTaleInfo (${len} entradas)`);
      }
      if (vs.uptimeData.engineCoolantTemperature != null) {
        console.log(`     ⭐ engineCoolantTemperature = ${vs.uptimeData.engineCoolantTemperature}`);
      }
    } else {
      console.log('  🔴 uptimeData AUSENTE.');
      console.log('     El bloque NO está habilitado para esta unidad.');
      console.log('     Reportar este output a Volvo.');
    }
  }

  console.log('');
  console.log('─'.repeat(70));
  console.log('Diagnóstico:');
  const conUptime = list.filter((vs) => vs.uptimeData).length;
  if (conUptime === list.length) {
    console.log(`  ✅ Las ${list.length} unidades devolvieron uptimeData.`);
    console.log('     → Confirmar a Volvo que está OK.');
    console.log('     → Próximo paso: actualizar telemetriaSnapshotScheduled');
    console.log('       para persistir uptimeData en TELEMETRIA_SNAPSHOTS.');
  } else if (conUptime > 0) {
    console.log(`  ⚠ ${conUptime}/${list.length} unidades con uptimeData.`);
    console.log('     → El feature está activo solo en algunas unidades.');
    console.log('     → Pedir a Volvo que extienda a las restantes.');
  } else {
    console.log('  ❌ Ninguna unidad devolvió uptimeData.');
    console.log('     → Reportar a Volvo el output de este probe.');
  }
  console.log('─'.repeat(70));
})().catch((e) => {
  console.error('error:', e);
  process.exit(1);
});
