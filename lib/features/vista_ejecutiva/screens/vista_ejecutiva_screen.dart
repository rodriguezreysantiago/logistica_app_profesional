// Pantalla "VISTA EJECUTIVA" — panorama rápido para directivos
// (Diego/Carlos) y admin/supervisor. Reúne data ya capturada en otros
// módulos en una sola pantalla con 2 tabs:
//
//   Tab 1 — TABLERO: KPIs grandes (viajes del mes, ICM flota, choferes
//           activos, alertas), gráficos de tendencia (ICM 12 semanas,
//           viajes/semana) y top 5 mejores/a mejorar.
//   Tab 2 — MAPA: posición en vivo de toda la flota (reusa el
//           AdminMapaFlotaScreen en modo embedded — mismo widget que
//           el menú "Mapa" del sidebar, pero acá ligado al panorama
//           ejecutivo).
//
// Diseño: AppScaffold con TabBar en el bottom. Cada tab se mantiene
// vivo entre cambios (AutomaticKeepAliveClientMixin) para que el
// Future del tablero no se re-trigerée cuando el usuario va y vuelve.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../fleet_map/screens/admin_mapa_flota_screen.dart';
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

class _VistaEjecutivaScreenState extends State<VistaEjecutivaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Vista ejecutiva',
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(60),
            border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(15)),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accentGreen,
            indicatorWeight: 3,
            labelColor: AppColors.accentGreen,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
            tabs: const [
              Tab(
                height: 42,
                icon: Icon(Icons.dashboard_customize, size: 18),
                iconMargin: EdgeInsets.only(bottom: 2),
                text: 'TABLERO',
              ),
              Tab(
                height: 42,
                icon: Icon(Icons.map, size: 18),
                iconMargin: EdgeInsets.only(bottom: 2),
                text: 'MAPA FLOTA',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TableroTab(),
          // Mapa de flota embebido — reusa el mismo widget de la
          // pantalla "Mapa" del sidebar (con su toolbar de filtros +
          // mapa + sheets de detalle), pero sin AppScaffold propio.
          AdminMapaFlotaScreen(embedded: true),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 1 — TABLERO (KPIs + gráficos + top choferes)
// =============================================================================

class _TableroTab extends StatefulWidget {
  const _TableroTab();

  @override
  State<_TableroTab> createState() => _TableroTabState();
}

class _TableroTabState extends State<_TableroTab>
    with AutomaticKeepAliveClientMixin {
  Future<KpisVistaEjecutiva>? _futureKpis;

  // Mantiene el state vivo al cambiar de tab — sin esto, el Future se
  // re-trigeraría cada vez que el usuario vuelve a la pestaña.
  @override
  bool get wantKeepAlive => true;

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
    super.build(context); // requerido por AutomaticKeepAliveClientMixin
    return RefreshIndicator(
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
        // Sección 2: gráficos de tendencia.
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
        // Sección 3: top 5 / a mejorar.
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
