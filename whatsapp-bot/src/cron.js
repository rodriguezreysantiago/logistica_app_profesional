// Cron interno del bot — Fase 2.
//
// Cada N minutos (default 60) recorre EMPLEADOS y VEHICULOS, calcula
// urgencia de cada vencimiento, y encola avisos automáticos en
// COLA_WHATSAPP. La idempotencia se garantiza con AVISOS_AUTOMATICOS_HISTORICO
// (ver historico.js): el mismo aviso (mismo nivel de urgencia, misma
// fecha de vencimiento) se envía una sola vez.
//
// AGRUPACIÓN POR CHOFER (2026-04-30): si un mismo chofer tiene 2+
// vencimientos para avisar en el mismo ciclo, mandamos UN solo mensaje
// con la lista completa en lugar de N mensajes separados. Eso reduce
// drásticamente la huella de bot ante WhatsApp (mensajes consecutivos
// al mismo número en pocos segundos = signal fuerte de spam) y le da
// al chofer toda la info de un saque.

const admin = require('firebase-admin');
const log = require('./logger');
const { enHorarioHabil } = require('./humano');
const aviso = require('./aviso_builder');
const avisoService = require('./aviso_service_builder');
const hist = require('./historico');
const health = require('./health');

// Intervalo entre services programados de tractores Volvo, en KM.
const INTERVALO_SERVICE_KM = 50000;

// Documentos auditados de EMPLEADOS — replica del listado en
// `lib/features/expirations/screens/admin_vencimientos_choferes_screen.dart`.
const DOCS_EMPLEADO = {
  'Licencia de Conducir': 'LICENCIA_DE_CONDUCIR',
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
    { etiqueta: 'Extintor Cabina', campoFecha: 'VENCIMIENTO_EXTINTOR_CABINA', campoBase: 'EXTINTOR_CABINA' },
    { etiqueta: 'Extintor Exterior', campoFecha: 'VENCIMIENTO_EXTINTOR_EXTERIOR', campoBase: 'EXTINTOR_EXTERIOR' },
  ],
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
 *
 * Parseo manual de YYYY-MM-DD para evitar el shift UTC vs local que
 * `new Date("YYYY-MM-DD")` aplica (medianoche UTC = 21h del día
 * anterior en ART → días corridos para atrás).
 */
function calcularDiasRestantes(fechaIso) {
  if (!fechaIso) return null;
  const str = String(fechaIso).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str);
  let venc;
  if (m) {
    venc = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
  } else {
    venc = new Date(str);
  }
  if (isNaN(venc.getTime())) return null;
  const hoy = new Date();
  const a = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const b = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate());
  const ms = b.getTime() - a.getTime();
  return Math.round(ms / (1000 * 60 * 60 * 24));
}

let _running = false;
let _timer = null;

function start(fs) {
  if (_timer) return;
  const enabled =
    String(process.env.AUTO_AVISOS_ENABLED || 'false').toLowerCase() === 'true';
  if (!enabled) {
    log.info(
      'Cron de avisos automáticos DESHABILITADO (AUTO_AVISOS_ENABLED=false). ' +
        'Habilitar en .env cuando confirmes que el bot envía bien.'
    );
    return;
  }

  const intervaloMin = parseInt(process.env.CRON_INTERVAL_MINUTES || '60', 10);
  log.info(`Cron de avisos automáticos HABILITADO (cada ${intervaloMin} min).`);
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
  const stats = { encolados: 0, agrupados: 0, salteados: 0, errores: 0 };

  try {
    // ─── Cargar empleados + índice patente → chofer ───
    const empleadosSnap = await db.collection('EMPLEADOS').get();
    const empleadosByDni = new Map();
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

    // ─── Recolectar items por chofer ───
    // Map<dni, { chofer, items: [{tipo, tipoDoc, dias, fecha, referencia, params}] }>
    // `params` se usa para el registro de idempotencia individual.
    const itemsPorChofer = new Map();

    function _addItem(dni, chofer, item) {
      if (!itemsPorChofer.has(dni)) {
        itemsPorChofer.set(dni, { chofer, items: [] });
      }
      itemsPorChofer.get(dni).items.push(item);
    }

    // 1) Vencimientos personales del chofer
    for (const [dni, emp] of empleadosByDni) {
      const data = emp.data;
      const telefono = data.TELEFONO ? String(data.TELEFONO) : null;
      if (!telefono) continue;

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
        _addItem(dni, emp, {
          tipo: 'vencimiento',
          tipoDoc: etiqueta,
          dias,
          fecha: fechaStr,
          referencia: null, // personal del chofer, sin referencia a unidad
          params,
        });
      }
    }

    // 2) Vencimientos de unidades (asignadas al chofer)
    const vehiculosSnap = await db.collection('VEHICULOS').get();
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      const specs = DOCS_VEHICULO[tipo];
      if (!specs) continue;

      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO ? String(chofer.data.TELEFONO) : null;
      if (!telefono) continue;

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
        _addItem(chofer.id, chofer, {
          tipo: 'vencimiento',
          tipoDoc: spec.etiqueta,
          dias,
          fecha: fechaStr,
          referencia: `${tipo} ${patente}`,
          params,
        });
      }
    }

    // 3) Service preventivo de TRACTORES
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      if (tipo !== 'TRACTOR') continue;

      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO ? String(chofer.data.TELEFONO) : null;
      if (!telefono) continue;

      const serviceDistanceKm = _resolverServiceDistance(v);
      if (serviceDistanceKm == null) continue;
      const urgencia = hist.urgenciaServicePara(serviceDistanceKm);
      if (!urgencia) continue;

      // Anclaje del ciclo del service (ver comentarios extensos en
      // versiones previas — bug C7 del code review).
      let anclaCiclo;
      if (v.ULTIMO_SERVICE_KM != null) {
        anclaCiclo = Math.round(Number(v.ULTIMO_SERVICE_KM));
      } else if (v.SERVICE_DISTANCE_KM != null) {
        anclaCiclo = Math.round(Number(v.KM_ACTUAL || 0) + Number(v.SERVICE_DISTANCE_KM || 0));
      } else {
        continue;
      }

      const params = {
        coleccion: 'VEHICULOS',
        docId: patente,
        campoBase: 'SERVICE',
        urgencia: urgencia.codigo,
        fechaVenc: String(anclaCiclo),
      };
      // Para SERVICE usamos `yaSeEnvioServiceMaxUrgencia` en lugar del
      // chequeo plano. Asi evitamos el rebote cuando la urgencia baja
      // dentro de la misma ancla (caso del admin que edita
      // ULTIMO_SERVICE_KM por error sin que el service realmente se haya
      // hecho). La escalada normal (urgencia sube) sigue funcionando
      // porque chequea solo niveles iguales o mayores.
      if (await hist.yaSeEnvioServiceMaxUrgencia(db, params)) {
        stats.salteados++;
        continue;
      }
      _addItem(chofer.id, chofer, {
        tipo: 'service',
        tipoDoc: 'Service',
        dias: serviceDistanceKm, // para service, "dias" es realmente KM (lo formatea aviso_builder)
        fecha: null,
        referencia: `${patente}`,
        params,
      });
    }

    // ─── Encolar mensajes (agrupados por chofer) ───
    for (const [dni, { chofer, items }] of itemsPorChofer) {
      if (items.length === 0) continue;
      const telefono = chofer.data.TELEFONO ? String(chofer.data.TELEFONO).trim() : null;
      if (!telefono) continue;
      const nombre = aviso.resolverNombreSaludo(chofer.data);

      let mensaje;
      let origen;
      if (items.length === 1) {
        // Un solo item — mensaje individual con variantes (texto más
        // natural y empático para casos sueltos).
        const item = items[0];
        if (item.tipo === 'service') {
          // Service usa builder dedicado.
          const v = vehiculosSnap.docs.find((d) => d.id === item.referencia.split(' ').pop());
          mensaje = avisoService.build({
            patente: item.referencia,
            marca: v ? v.data().MARCA : '',
            modelo: v ? v.data().MODELO : '',
            serviceDistanceKm: item.dias,
            destinatarioNombre: nombre,
          });
          if (!mensaje) {
            log.warn(`Service ${item.referencia}: datos inválidos, salto.`);
            continue;
          }
          origen = 'cron_aviso_service';
        } else {
          // Vencimiento normal.
          const titulo = item.referencia
            ? `${item.referencia}` // ya viene formateado "TRACTOR AB123"
            : (chofer.data.NOMBRE || dni);
          mensaje = aviso.build({
            item: {
              coleccion: item.params.coleccion,
              tipoDoc: item.tipoDoc,
              docId: item.params.docId,
              titulo,
              fecha: item.fecha,
              dias: item.dias,
            },
            destinatarioNombre: nombre,
          });
          origen = 'cron_aviso_vencimiento';
        }
      } else {
        // 2+ items — mensaje agrupado.
        mensaje = aviso.buildAgrupado({
          destinatarioNombre: nombre,
          items: items.map((it) => ({
            tipo: it.tipo,
            tipoDoc: it.tipoDoc,
            dias: it.dias,
            fecha: it.fecha,
            referencia: it.referencia,
          })),
        });
        origen = 'cron_aviso_agrupado';
        stats.agrupados++;
      }

      // Encolar UN solo doc en COLA_WHATSAPP.
      try {
        const colaRef = await db.collection(fs.COLECCION).add({
          telefono,
          mensaje,
          estado: fs.ESTADO.pendiente,
          encolado_en: admin.firestore.FieldValue.serverTimestamp(),
          enviado_en: null,
          error: null,
          intentos: 0,
          origen,
          destinatario_coleccion: 'EMPLEADOS',
          destinatario_id: dni,
          campo_base: items.length === 1 ? items[0].params.campoBase : 'AGRUPADO',
          admin_dni: 'BOT',
          admin_nombre: 'Bot automático',
          // Si es agrupado, guardamos también qué papeles incluyó —
          // útil para debugging y para que la pantalla de cola muestre
          // un resumen en vez de "AGRUPADO" pelado.
          items_agrupados: items.length > 1
            ? items.map((it) => ({
                tipoDoc: it.tipoDoc,
                campoBase: it.params.campoBase,
                coleccion: it.params.coleccion,
                docId: it.params.docId,
                fecha: it.fecha,
                dias: it.dias,
              }))
            : null,
        });

        // Registrar idempotencia POR ITEM (cada papel queda marcado
        // individualmente, así si mañana se suma un papel nuevo solo
        // ese se va a re-encolar — los demás ya están "marcados").
        for (const item of items) {
          await hist.registrar(db, item.params, colaRef.id);
        }

        stats.encolados++;
        if (items.length === 1) {
          log.info(`+ Encolado: ${dni} ${items[0].tipoDoc} → ${colaRef.id}`);
        } else {
          log.info(
            `+ Encolado AGRUPADO: ${dni} (${items.length} papeles) → ${colaRef.id}`
          );
        }
      } catch (e) {
        stats.errores++;
        log.error(`No se pudo encolar para ${dni}: ${e.message}`);
      }
    }

    log.info(
      `Cron ciclo cerrado: encolados=${stats.encolados} ` +
        `(de los cuales ${stats.agrupados} agrupados) ` +
        `salteados=${stats.salteados} errores=${stats.errores}`
    );
    health.registrarCicloCron(stats);
  } catch (e) {
    log.error(`Cron falló: ${e.stack || e.message}`);
    health.registrarError('cron', e.message);
  } finally {
    _running = false;
  }
}

/**
 * Calcula `serviceDistanceKm` para un doc de VEHICULOS.
 * Espejo de `_resolverServiceDistance` en el cliente Dart.
 */
function _resolverServiceDistance(v) {
  const api = Number(v.SERVICE_DISTANCE_KM);
  if (!isNaN(api) && v.SERVICE_DISTANCE_KM != null) return api;

  const ultimo = Number(v.ULTIMO_SERVICE_KM);
  const actual = Number(v.KM_ACTUAL);
  if (!isNaN(ultimo) && !isNaN(actual) && v.ULTIMO_SERVICE_KM != null && v.KM_ACTUAL != null) {
    return ultimo + INTERVALO_SERVICE_KM - actual;
  }
  return null;
}

/**
 * Fuerza una corrida del cron AHORA, ignorando el setInterval. Usado
 * por el comando admin /forzar-cron de WhatsApp.
 */
async function forzarRunOnce(fs) {
  if (_running) return null;
  await _runOnce(fs);
  return null;
}

module.exports = {
  start,
  stop,
  forzarRunOnce,
  calcularDiasRestantes,
  DOCS_EMPLEADO,
  DOCS_VEHICULO,
  INTERVALO_SERVICE_KM,
};
