// Cron interno del bot — Fase 2.
//
// Cada N minutos (default 60) recorre EMPLEADOS y VEHICULOS, calcula
// urgencia de cada vencimiento, y encola avisos automáticos en
// COLA_WHATSAPP. La idempotencia se garantiza con AVISOS_AUTOMATICOS_HISTORICO
// (ver historico.js): el mismo aviso (mismo nivel de urgencia, misma
// fecha de vencimiento) se envía una sola vez.
//
// Se desactiva por default (`AUTO_AVISOS_ENABLED=false`) para que el
// primer arranque no genere sorpresas. El admin lo activa cuando
// confirme que el bot envía bien manualmente.

const admin = require('firebase-admin');
const log = require('./logger');
const { enHorarioHabil } = require('./humano');
const aviso = require('./aviso_builder');
const hist = require('./historico');

// Documentos auditados de EMPLEADOS — replica del listado en
// `lib/features/expirations/screens/admin_vencimientos_choferes_screen.dart`.
// Si en el futuro se centraliza en algún lado, leerlo de ahí.
const DOCS_EMPLEADO = {
  Licencia: 'LICENCIA_DE_CONDUCIR',
  Preocupacional: 'PREOCUPACIONAL',
  'Manejo Defensivo': 'CURSO_DE_MANEJO_DEFENSIVO',
  ART: 'ART',
  'F. 931': '931',
  'Seguro de Vida': 'SEGURO_DE_VIDA',
  Sindicato: 'LIBRE_DE_DEUDA_SINDICAL',
};

// Vencimientos auditados de VEHICULOS por tipo. Replica de
// `lib/core/constants/vencimientos_config.dart`. Mantener sincronizado.
const DOCS_VEHICULO = {
  TRACTOR: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
    {
      etiqueta: 'Extintor Cabina',
      campoFecha: 'VENCIMIENTO_EXTINTOR_CABINA',
      campoBase: 'EXTINTOR_CABINA',
    },
    {
      etiqueta: 'Extintor Exterior',
      campoFecha: 'VENCIMIENTO_EXTINTOR_EXTERIOR',
      campoBase: 'EXTINTOR_EXTERIOR',
    },
  ],
  // Enganches (BATEA, TOLVA, etc.) tienen RTO + Seguro.
  // Si tu app define más tipos con sus propios vencimientos, sumalos acá.
  BATEA: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  TOLVA: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  BIVUELCO: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  TANQUE: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  ACOPLADO: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
};

/**
 * Calcula los días restantes hasta `fechaIso` (`YYYY-MM-DD` o ISO).
 * Negativo si la fecha ya pasó. Devuelve `null` si la fecha es inválida.
 */
function calcularDiasRestantes(fechaIso) {
  if (!fechaIso) return null;
  const venc = new Date(fechaIso);
  if (isNaN(venc.getTime())) return null;
  // Normalizamos a medianoche local para que el cálculo sea estable
  // independientemente de a qué hora corre el cron.
  const hoy = new Date();
  const a = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const b = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate());
  const ms = b.getTime() - a.getTime();
  return Math.round(ms / (1000 * 60 * 60 * 24));
}

let _running = false;
let _timer = null;

/**
 * Arranca el cron si está habilitado. Idempotente: una segunda
 * llamada no duplica el timer.
 *
 * @param {object} fs - El módulo `firestore.js` (para reutilizar la
 *   constante COLECCION y los helpers de la cola).
 */
function start(fs) {
  if (_timer) return;
  const enabled =
    String(process.env.AUTO_AVISOS_ENABLED || 'false').toLowerCase() ===
    'true';
  if (!enabled) {
    log.info(
      'Cron de avisos automáticos DESHABILITADO (AUTO_AVISOS_ENABLED=false). ' +
        'Habilitar en .env cuando confirmes que el bot envía bien.'
    );
    return;
  }

  const intervaloMin = parseInt(
    process.env.CRON_INTERVAL_MINUTES || '60',
    10
  );
  log.info(
    `Cron de avisos automáticos HABILITADO (cada ${intervaloMin} min).`
  );
  // Primera corrida 30s después de iniciar — le damos tiempo a wwebjs
  // a estabilizarse antes de escribir a la cola.
  setTimeout(() => _runOnce(fs), 30000);
  _timer = setInterval(() => _runOnce(fs), intervaloMin * 60 * 1000);
}

function stop() {
  if (_timer) {
    clearInterval(_timer);
    _timer = null;
  }
}

async function _runOnce(fs) {
  if (_running) {
    log.warn('Cron previo todavía corriendo, salto este ciclo.');
    return;
  }
  if (!enHorarioHabil()) {
    log.debug('Cron salta — fuera de horario hábil.');
    return;
  }
  _running = true;

  const db = fs.inicializar();
  const stats = { encolados: 0, salteados: 0, errores: 0 };

  try {
    const empleadosSnap = await db.collection('EMPLEADOS').get();
    const empleadosByDni = new Map();
    // Índice inverso patente → empleado, pre-computado una vez por
    // ciclo. Antes hacíamos _buscarChofer() linealmente para cada
    // vencimiento de unidad, que era O(n*m) con n vehículos × m
    // empleados. Para una flota grande de 500 unidades empezaba a
    // doler — para Vecchi era despreciable, pero igual conviene.
    const choferByPatente = new Map();
    for (const doc of empleadosSnap.docs) {
      const data = doc.data();
      const emp = { id: doc.id, data };
      empleadosByDni.set(doc.id.trim(), emp);
      const veh = String(data.VEHICULO || '').trim().toUpperCase();
      const eng = String(data.ENGANCHE || '').trim().toUpperCase();
      if (veh && veh !== '-') choferByPatente.set(veh, emp);
      if (eng && eng !== '-') choferByPatente.set(eng, emp);
    }

    // ─── 1) Vencimientos personales del chofer ───
    for (const [dni, emp] of empleadosByDni) {
      const data = emp.data;
      const telefono = data.TELEFONO ? String(data.TELEFONO) : null;
      if (!telefono) continue; // sin teléfono, no podemos avisar

      const nombre = aviso.extraerPrimerNombre(data.NOMBRE);
      for (const [etiqueta, campoBase] of Object.entries(DOCS_EMPLEADO)) {
        const fechaStr = data[`VENCIMIENTO_${campoBase}`];
        const dias = calcularDiasRestantes(fechaStr);
        if (dias == null) continue;
        const urgencia = hist.urgenciaPara(dias);
        if (!urgencia) continue;

        const params = {
          coleccion: 'EMPLEADOS',
          docId: dni,
          campoBase,
          urgencia: urgencia.codigo,
          fechaVenc: fechaStr,
        };
        if (await hist.yaSeEnvio(db, params)) {
          stats.salteados++;
          continue;
        }

        const mensaje = aviso.build({
          item: {
            coleccion: 'EMPLEADOS',
            tipoDoc: etiqueta,
            docId: dni,
            titulo: data.NOMBRE || dni,
            fecha: fechaStr,
            dias,
          },
          destinatarioNombre: nombre,
        });

        try {
          const colaRef = await db.collection(fs.COLECCION).add({
            telefono: telefono.trim(),
            mensaje,
            estado: fs.ESTADO.pendiente,
            encolado_en: admin.firestore.FieldValue.serverTimestamp(),
            enviado_en: null,
            error: null,
            intentos: 0,
            origen: 'cron_aviso_vencimiento',
            destinatario_coleccion: 'EMPLEADOS',
            destinatario_id: dni,
            campo_base: campoBase,
            admin_dni: 'BOT',
            admin_nombre: 'Bot automático',
          });
          await hist.registrar(db, params, colaRef.id);
          stats.encolados++;
          log.info(
            `+ Encolado auto: ${etiqueta} de ${dni} (${urgencia.codigo}, ` +
              `${dias} días) → ${colaRef.id}`
          );
        } catch (e) {
          stats.errores++;
          log.error(`No se pudo encolar ${dni}/${campoBase}: ${e.message}`);
        }
      }
    }

    // ─── 2) Vencimientos de unidades (RTO, seguros, extintores) ───
    const vehiculosSnap = await db.collection('VEHICULOS').get();
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      const specs = DOCS_VEHICULO[tipo];
      if (!specs) continue;

      // El destinatario es el chofer asignado a la unidad. Si nadie la
      // tiene asignada, no podemos avisar — el admin la verá en la
      // auditoría manual.
      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO
        ? String(chofer.data.TELEFONO)
        : null;
      if (!telefono) continue;
      const nombre = aviso.extraerPrimerNombre(chofer.data.NOMBRE);

      for (const spec of specs) {
        const fechaStr = v[spec.campoFecha];
        const dias = calcularDiasRestantes(fechaStr);
        if (dias == null) continue;
        const urgencia = hist.urgenciaPara(dias);
        if (!urgencia) continue;

        const params = {
          coleccion: 'VEHICULOS',
          docId: patente,
          campoBase: spec.campoBase,
          urgencia: urgencia.codigo,
          fechaVenc: fechaStr,
        };
        if (await hist.yaSeEnvio(db, params)) {
          stats.salteados++;
          continue;
        }

        const mensaje = aviso.build({
          item: {
            coleccion: 'VEHICULOS',
            tipoDoc: spec.etiqueta,
            docId: patente,
            titulo: `${tipo} - ${patente}`,
            fecha: fechaStr,
            dias,
          },
          destinatarioNombre: nombre,
        });

        try {
          const colaRef = await db.collection(fs.COLECCION).add({
            telefono: telefono.trim(),
            mensaje,
            estado: fs.ESTADO.pendiente,
            encolado_en: admin.firestore.FieldValue.serverTimestamp(),
            enviado_en: null,
            error: null,
            intentos: 0,
            origen: 'cron_aviso_vencimiento',
            destinatario_coleccion: 'VEHICULOS',
            destinatario_id: patente,
            campo_base: spec.campoBase,
            admin_dni: 'BOT',
            admin_nombre: 'Bot automático',
          });
          await hist.registrar(db, params, colaRef.id);
          stats.encolados++;
          log.info(
            `+ Encolado auto: ${spec.etiqueta} de ${patente} ` +
              `(${urgencia.codigo}, ${dias} días) → chofer ${chofer.id}`
          );
        } catch (e) {
          stats.errores++;
          log.error(
            `No se pudo encolar ${patente}/${spec.campoBase}: ${e.message}`
          );
        }
      }
    }

    log.info(
      `Cron ciclo cerrado: encolados=${stats.encolados} ` +
        `salteados=${stats.salteados} errores=${stats.errores}`
    );
  } catch (e) {
    log.error(`Cron falló: ${e.stack || e.message}`);
  } finally {
    _running = false;
  }
}

// `_buscarChofer` removida — reemplazada por el índice inverso
// `choferByPatente` que se construye una vez al inicio del ciclo y
// permite lookup O(1) en lugar de O(n) por cada vencimiento.

module.exports = {
  start,
  stop,
  // Exportados para tests / uso interno:
  calcularDiasRestantes,
  DOCS_EMPLEADO,
  DOCS_VEHICULO,
};
