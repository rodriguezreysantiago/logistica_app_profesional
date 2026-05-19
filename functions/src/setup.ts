// Setup y constants globales — compartido entre index.ts y los módulos
// extraidos en el split 2026-05-18.
//
// IMPORTANTE: este archivo MUST evaluarse antes que cualquier código que
// use `db` o `auth`. Como TypeScript módulos se cachean por proceso,
// alcanza con que sea importado al menos una vez (desde index.ts o
// transitivamente desde cualquier módulo).
//
// Pattern: index.ts hace `import "./setup";` al principio (lado-efecto:
// dispara initializeApp + setGlobalOptions), y los demás archivos
// importan los símbolos puntuales (`db`, `auth`, constants).

import { setGlobalOptions } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

// Inicialización del Admin SDK (una sola vez por instancia).
initializeApp();

// Configuración global: límite de instancias concurrentes para que un
// loop de login no me funda la cuenta. La region es southamerica-east1
// (São Paulo) para estar en el mismo DC que Firestore — eso elimina el
// hop us-central1 ↔ sa-east1 en cada read/write (~150ms por op).
setGlobalOptions({
  region: "southamerica-east1",
  maxInstances: 10,
  // El timeout por defecto es 60 segundos, suficiente.
});

export const db = getFirestore();
export const auth = getAuth();

// ============================================================================
// Configuración de rate limiting
// ============================================================================
// Después de N intentos fallidos consecutivos sobre el mismo DNI, se
// bloquea ese DNI por X minutos. Implementado server-side en la
// colección LOGIN_ATTEMPTS (clave = hash corto del DNI para no exponer
// el dato en el path del documento).
//
// El reset del contador es automático: cualquier login OK lo borra.
// Después del bloqueo, el próximo intento fallido empieza un nuevo
// ciclo desde 1.
//
// Endurecido el 2026-05-03: pasó de 5 intentos / 5 min a 3 intentos /
// 15 min. Una flota chica (~50 empleados) tiene casi cero falsos
// positivos legítimos (el chofer/admin sabe su DNI o tiene "recordar
// DNI" del login), así que 3 intentos cubre los typos genuinos.
// Fuerza bruta: con la config vieja un atacante podía probar 60 combos
// por hora; con la nueva, 12. Reducción 5x del techo de tasa.
export const MAX_INTENTOS_FALLIDOS = 3;
export const BLOQUEO_DURACION_MS = 15 * 60 * 1000; // 15 minutos

// Banner de etapa de prueba — vaciado 2026-05-18 (decision Santiago).
// El bot opera 24/7 con choferes/admins reales onboardeados, ya no
// aplica el disclaimer. Mantenemos la constante como string vacio para
// no romper las ~25 concatenaciones existentes (concat con "" es no-op).
// Si en el futuro se vuelve a necesitar marcar mensajes como "prueba",
// restaurar el contenido aca.
export const BANNER_TESTING = "";
