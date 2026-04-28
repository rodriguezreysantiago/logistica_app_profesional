import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_widgets.dart';
import '../providers/sync_dashboard_provider.dart';

/// Dashboard de observabilidad del sync con Volvo.
///
/// Muestra métricas en tiempo real del AutoSyncService:
/// - Activos / éxito / errores en este ciclo
/// - Total acumulado, tasa de éxito, latencia promedio
/// - Progreso del ciclo actual (cuántos vehículos van procesados)
class SyncDashboardScreen extends StatelessWidget {
  const SyncDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Sync Dashboard',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Resetear contadores',
          onPressed: () => context.read<SyncDashboardProvider>().reset(),
        ),
      ],
      body: Consumer<SyncDashboardProvider>(
        builder: (context, dash, _) => _Body(dash: dash),
      ),
    );
  }
}

// =============================================================================
// CUERPO DE LA PANTALLA
// =============================================================================

class _Body extends StatelessWidget {
  final SyncDashboardProvider dash;
  const _Body({required this.dash});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cards principales (activos / éxito / errores)
          const _SectionHeader(label: 'Estado actual'),
          const SizedBox(height: 8),
          Row(
            children: [
              _LiveCard(
                label: 'Activos',
                value: dash.activeSyncs.toString(),
                color: Colors.orangeAccent,
                icon: Icons.sync,
              ),
              const SizedBox(width: 10),
              _LiveCard(
                label: 'Éxito',
                value: dash.successSyncs.toString(),
                color: Colors.greenAccent,
                icon: Icons.check_circle,
              ),
              const SizedBox(width: 10),
              _LiveCard(
                label: 'Errores',
                value: dash.failedSyncs.toString(),
                color: Colors.redAccent,
                icon: Icons.error,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Progreso del ciclo actual
          if (dash.cycleTotal > 0) ...[
            const _SectionHeader(label: 'Ciclo actual'),
            const SizedBox(height: 8),
            _CicloProgress(
              cycle: dash.cycle,
              procesados: dash.cycleProcessed,
              total: dash.cycleTotal,
            ),
            const SizedBox(height: 24),
          ],

          // Métricas acumuladas
          const _SectionHeader(label: 'Métricas globales'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _StatTile(
                label: 'Total syncs',
                value: dash.totalSyncs.toString(),
              ),
              _StatTile(
                label: 'Tasa de éxito',
                value: '${(dash.successRate * 100).toStringAsFixed(1)}%',
                accent: dash.successRate >= 0.9
                    ? Colors.greenAccent
                    : (dash.successRate >= 0.7
                        ? Colors.orangeAccent
                        : Colors.redAccent),
              ),
              _StatTile(
                label: 'Latencia avg',
                value: '${dash.avgLatencyMs.toStringAsFixed(0)} ms',
              ),
              _StatTile(
                label: 'Último sync',
                value: dash.lastSyncAt != null
                    ? dash.lastSyncAt.toString().substring(11, 19)
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// COMPONENTES
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _LiveCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(14),
        margin: EdgeInsets.zero,
        borderColor: color.withAlpha(60),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CicloProgress extends StatelessWidget {
  final int cycle;
  final int procesados;
  final int total;

  const _CicloProgress({
    required this.cycle,
    required this.procesados,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (procesados / total).clamp(0.0, 1.0);
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse,
                  color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Ciclo #$cycle',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '$procesados / $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _StatTile({
    required this.label,
    required this.value,
    this.accent = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
