import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_dashboard_provider.dart';

class SyncDashboardScreen extends StatelessWidget {
  const SyncDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sync Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<SyncDashboardProvider>().reset();
            },
          ),
        ],
      ),
      body: Consumer<SyncDashboardProvider>(
        builder: (context, dash, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildTopCards(dash),
                const SizedBox(height: 16),
                _buildStatsGrid(dash),
                const SizedBox(height: 16),
                _buildLiveStatus(dash),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================
  // TOP CARDS
  // =========================

  Widget _buildTopCards(SyncDashboardProvider dash) {
    return Row(
      children: [
        _card(
          title: "Activos",
          value: dash.activeSyncs.toString(),
          color: Colors.orange,
          icon: Icons.sync,
        ),
        const SizedBox(width: 10),
        _card(
          title: "Éxito",
          value: dash.successSyncs.toString(),
          color: Colors.green,
          icon: Icons.check_circle,
        ),
        const SizedBox(width: 10),
        _card(
          title: "Errores",
          value: dash.failedSyncs.toString(),
          color: Colors.red,
          icon: Icons.error,
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }

  // =========================
  // STATS GRID
  // =========================

  Widget _buildStatsGrid(SyncDashboardProvider dash) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.8,
      children: [
        _statTile("Total Syncs", dash.totalSyncs.toString()),
        _statTile(
          "Success Rate",
          "${(dash.successRate * 100).toStringAsFixed(1)}%",
        ),
        _statTile(
          "Avg Latency",
          "${dash.avgLatencyMs.toStringAsFixed(0)} ms",
        ),
        _statTile(
          "Último Sync",
          dash.lastSyncAt != null
              ? dash.lastSyncAt.toString().substring(11, 19)
              : "-",
        ),
      ],
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // =========================
  // LIVE STATUS
  // =========================

  Widget _buildLiveStatus(SyncDashboardProvider dash) {
    final snapshot = dash.snapshot();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Live Snapshot",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(snapshot.toString()),
        ],
      ),
    );
  }
}