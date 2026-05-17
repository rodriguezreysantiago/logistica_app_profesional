// Pantalla "VISTA EJECUTIVA" — tablero CEO con los KPIs principales
// de la operación. Pensado como panorama rápido para directivos
// (Diego/Carlos) y para que admin/supervisor vea el estado general
// en 5 segundos antes de meterse en módulos específicos.
//
// Identidad clara: panorámica de NÚMEROS (KPIs + tendencias + gente).
// Para "dónde está cada camión ahora" → el módulo "Mapa" del sidebar,
// que ya cumple ese rol. Decisión Santiago 2026-05-16: no duplicar
// el mapa acá (un solo punto de entrada por feature).
//
// Estructura:
//   - PANORAMA DEL MES: 4 KPI cards (viajes, ICM, choferes, alertas)
//   - EFICIENCIA OPERATIVA: 1 card grande km/L últimos 30 días
//   - TENDENCIAS: 2 gráficos (ICM 12 semanas, viajes/semana 8)
//   - PERSONAS: top 5 mejores + top 5 a mejorar

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/vista_ejecutiva_service.dart';
import '../widgets/kpi_grande_card.dart';
import '../widgets/tendencia_icm_chart.dart';
import '../widgets/top_choferes_lista.dart';
import '../widgets/viajes_semanales_chart.dart';

class VistaEjecutivaScreen extends StatefulWidget {
  const VistaEjecutivaScreen({super.key});

  @override
  State<VistaEjecutivaScreen> createState() => _VistaEjecutivaScreenState();
}

class _VistaEjecutivaScreenState extends State<VistaEjecutivaScreen> {
  Future<KpisVistaEjecutiva>? _futureKpis;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    setState(() {
      _futureKpis = VistaEjecutivaService.cargar(
        db: FirebaseFirestore.instance,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Vista ejecutiva',
      body: RefreshIndicator(
        onRefresh: () async => _cargar(),
        color: AppColors.accentGreen,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<KpisVistaEjecutiva>(
          future: _futureKpis,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: CircularProgressIndicator(
                    color: AppColors.accentGreen,
                  ),
                ),
              );
            }
            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.accentRed, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'No se pudieron cargar los KPIs',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            snap.error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: _cargar,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            final kpis = snap.data!;
            return _TableroContent(kpis: kpis);
          },
        ),
      ),
    );
  }
}

class _TableroContent extends StatelessWidget {
  final KpisVistaEjecutiva kpis;
  const _TableroContent({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final esDesktop = MediaQuery.of(context).size.width >= 800;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        const _SectionLabel('PANORAMA DEL MES'),
        const SizedBox(height: 10),
        // Fila 1: 4 KPI cards grandes. 2 columnas mobile, 4 desktop.
        GridView.count(
          crossAxisCount: esDesktop ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: esDesktop ? 1.0 : 0.85,
          children: [
            KpiGrandeCard.mes(
              label: 'Viajes del mes',
              kpi: kpis.viajesDelMes,
              icono: Icons.local_shipping,
              color: AppColors.accentPurple,
              mejorEsSubir: true,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.adminLogisticaViajes),
            ),
            KpiGrandeCard.icm(
              label: 'ICM flota',
              kpi: kpis.icmFlota,
              icono: Icons.leaderboard,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.adminIcmReporteSemanal),
            ),
            KpiGrandeCard.simple(
              label: 'Choferes activos',
              kpi: kpis.choferesActivos,
              icono: Icons.badge,
              color: AppColors.accentBlue,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.adminPersonalLista),
            ),
            KpiGrandeCard.simple(
              label: 'Alertas críticas',
              kpi: kpis.alertasCriticas,
              icono: Icons.warning_amber_rounded,
              color: kpis.alertasCriticas.valor > 0
                  ? AppColors.accentRed
                  : AppColors.accentGreen,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.vencimientosCalendario),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Eficiencia operativa — card destacada full-width (mobile) o
        // media pantalla (desktop). Va sola en su seccion porque es el
        // KPI diferencial que YPF/Vecchi miran como indicador clave de
        // operacion + conducta de los choferes.
        const _SectionLabel('EFICIENCIA OPERATIVA'),
        const SizedBox(height: 10),
        if (esDesktop)
          Row(
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.45,
                child: KpiGrandeCard.eficiencia(
                  label: 'Eficiencia combustible · 30 días',
                  kpi: kpis.eficienciaCombustible,
                  icono: Icons.local_gas_station,
                  onTap: () => Navigator.pushNamed(
                      context, AppRoutes.adminEcoDriving),
                ),
              ),
            ],
          )
        else
          KpiGrandeCard.eficiencia(
            label: 'Eficiencia combustible · 30 días',
            kpi: kpis.eficienciaCombustible,
            icono: Icons.local_gas_station,
            onTap: () => Navigator.pushNamed(
                context, AppRoutes.adminEcoDriving),
          ),
        const SizedBox(height: 24),
        // Sección 3: gráficos de tendencia.
        const _SectionLabel('TENDENCIAS'),
        const SizedBox(height: 10),
        if (esDesktop)
          // En desktop van uno al lado del otro.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TendenciaIcmChart(
                  puntos: kpis.tendenciaIcm,
                  titulo: 'ICM promedio · últimas 12 semanas',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ViajesSemanalesChart(
                  puntos: kpis.viajesPorSemana,
                  titulo: 'Viajes por semana · últimas 8',
                ),
              ),
            ],
          )
        else ...[
          TendenciaIcmChart(
            puntos: kpis.tendenciaIcm,
            titulo: 'ICM promedio · últimas 12 semanas',
          ),
          const SizedBox(height: 10),
          ViajesSemanalesChart(
            puntos: kpis.viajesPorSemana,
            titulo: 'Viajes por semana · últimas 8',
          ),
        ],
        const SizedBox(height: 24),
        // Sección 4: top 5 / a mejorar.
        const _SectionLabel('PERSONAS'),
        const SizedBox(height: 10),
        if (esDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TopChoferesLista(
                  titulo: 'TOP 5 — MEJORES CHOFERES',
                  icono: Icons.emoji_events,
                  colorTitulo: AppColors.accentGreen,
                  items: kpis.top5Mejores,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TopChoferesLista(
                  titulo: 'TOP 5 — A MEJORAR',
                  icono: Icons.priority_high,
                  colorTitulo: AppColors.accentRed,
                  items: kpis.top5Peores,
                ),
              ),
            ],
          )
        else ...[
          TopChoferesLista(
            titulo: 'TOP 5 — MEJORES CHOFERES',
            icono: Icons.emoji_events,
            colorTitulo: AppColors.accentGreen,
            items: kpis.top5Mejores,
          ),
          const SizedBox(height: 10),
          TopChoferesLista(
            titulo: 'TOP 5 — A MEJORAR',
            icono: Icons.priority_high,
            colorTitulo: AppColors.accentRed,
            items: kpis.top5Peores,
          ),
        ],
        const SizedBox(height: 24),
        // Footer compacto con info de actualización.
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Tirá hacia abajo para actualizar · Datos pre-calculados cada 5 min',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String texto;
  const _SectionLabel(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppColors.accentGreen,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
