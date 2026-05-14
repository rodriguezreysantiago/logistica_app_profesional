# Pendientes follow-up

Cosas que requieren acción nuestra en una fecha específica. Para roadmap general
del proyecto, ver `ESTADO_PROYECTO.md`. Para procedimientos operativos, `RUNBOOK.md`.

Convención: orden cronológico (los próximos arriba). Sacar el ítem cuando se ejecuta.

---

## 📅 2026-05-15 (jue) o 2026-05-16 (vie) — Análisis de eventos Sitrack

**Contexto**: el cron `sitrackEventosPoller` se deployó el 2026-05-13 21:38 ART y
empezó a llenar la colección `SITRACK_EVENTOS` desde el endpoint
`/files/reports` que Sitrack acaba de activar. Primer ciclo: 35 eventos en
29 KB. Segundo ciclo (5 min después): 13 eventos en 10 KB.

**Acción**: una vez que pasen 24-48h con el cron acumulando data, correr:

```powershell
cd "C:\Users\Colo Logistica\coopertrans_movil"
node scripts/analizar_sitrack_eventos.js --horas 36
```

**Qué responde el script**:
- Top tipos de evento por frecuencia.
- Cobertura por categoría de consumidor potencial: jornada / viajes /
  combustible / conducción peligrosa / fatiga MobileEye / mantenimiento /
  puertas-seguridad.
- Cobertura operativa: cuántos eventos tienen chofer identificado,
  trailer, límite de velocidad cartográfico.
- Recomendación: qué consumidor armar primero según los datos reales.

**Decisión a tomar después del análisis**:
- Si una categoría domina (ej. JORNADA con > 40% del total) → arrancar a
  codear ese consumidor (vigilador v2, auto-poblar viajes, anti-robo
  combustible, etc.).
- Si todas las categorías vienen pobres → escalar a Sitrack para activar
  más tipos de evento por unidad.

**Output esperado a guardar**: pegar el resultado en el chat de Claude para
priorizar la próxima feature.
