# Scripts deprecated

Scripts que ya no sirven en el flujo operativo pero se mantienen versionados
por arqueología (entender qué se hizo en el pasado, o servir de plantilla
para script nuevo equivalente).

Cada script tiene `process.exit(1)` o `console.error` al inicio que aborta
la ejecución — si alguien lo corre por error, no rompe nada.

## Listado

| Script | Reemplazo | Deprecated |
|---|---|---|
| `auditar_jornadas_dia.js` | Necesita reescritura para leer `JORNADAS` (modelo v2) | 2026-05-16 |
| `diagnosticar_jornadas_excesos.js` | `resumenExcesosJornadaDiario` en Cloud Functions es la fuente de verdad | 2026-05-16 |
| `diagnosticar_vigilador_chofer.js` | Necesita reescritura: leer `JORNADAS` + `SITRACK_POSICIONES/{patente}` | 2026-05-16 |
| `resetear_jornada_chofer.js` | Reset manual en Firestore console; o script nuevo sobre `JORNADAS` | 2026-05-16 |

Todos los anteriores apuntan a `JORNADAS_CHOFER` (colección legacy migrada
a `JORNADAS` el 2026-05-15 con `limpiar_jornadas_chofer_legacy.js`).

## Cuándo borrar definitivamente

Cuando hayan pasado >6 meses sin que nadie consulte alguno de estos
scripts y haya certeza de que la lógica viva en otro lado (vigilador v2
en `functions/src/jornadas_v2.ts`).
