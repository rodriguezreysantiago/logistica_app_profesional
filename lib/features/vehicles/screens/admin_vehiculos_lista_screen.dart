import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/formatters.dart';
import '../providers/vehiculo_provider.dart';

import 'admin_vehiculo_form_screen.dart';
import 'admin_vehiculo_alta_screen.dart';

class AdminVehiculosListaScreen extends StatefulWidget {
  const AdminVehiculosListaScreen({super.key});

  @override
  State<AdminVehiculosListaScreen> createState() =>
      _AdminVehiculosListaScreenState();
}

class _AdminVehiculosListaScreenState
    extends State<AdminVehiculosListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VehiculoProvider>().init();
    });

    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchText = _searchController.text.toUpperCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Gestión de Flota"),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(110),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: "Buscar patente...",
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: "TRACTORES"),
                      Tab(text: "BATEAS"),
                      Tab(text: "TOLVAS"),
                    ],
                  ),
                ],
              ),
            ),
          ),

          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminVehiculoAltaScreen(),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),

          body: TabBarView(
            children: [
              _buildListaFiltrada("TRACTOR"),
              _buildListaFiltrada("BATEA"),
              _buildListaFiltrada("TOLVA"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaFiltrada(String tipoVehiculo) {
    return Consumer<VehiculoProvider>(
      builder: (context, provider, _) {
        return StreamBuilder<QuerySnapshot>(
          stream: provider.getVehiculosPorTipo(tipoVehiculo),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final lista = snapshot.data!.docs.where((doc) {
              final patente = doc.id.toUpperCase();
              return patente.contains(_searchText);
            }).toList();

            if (lista.isEmpty) {
              return const Center(child: Text("Sin resultados"));
            }

            return ListView.builder(
              itemCount: lista.length,
              itemBuilder: (context, index) {
                final doc = lista[index];
                final data = doc.data() as Map<String, dynamic>;

                final patente = doc.id;
                final vin = data['VIN'] ?? '';

                return Selector<VehiculoProvider, Map<String, dynamic>>(
                  selector: (_, p) => {
                    "loading": p.isLoading(patente),
                    "error": p.getError(patente),
                    "success": p.isSuccess(patente),
                  },
                  builder: (context, state, child) {
                    final bool isLoading = state["loading"];
                    final String? error = state["error"];
                    final bool success = state["success"];

                    return ExpansionTile(
                      title: Row(
                        children: [
                          Text(patente),

                          const SizedBox(width: 10),

                          if (isLoading)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),

                          if (success)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                            ),

                          if (error != null)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.error,
                                  color: Colors.red, size: 16),
                            ),
                        ],
                      ),

                      subtitle: Text(data['MARCA'] ?? 'S/M'),

                      onExpansionChanged: (open) async {
                        if (!open) return;
                        if (data['MARCA'] != 'VOLVO') return;
                        if (vin.toString().isEmpty) return;

                        final provider =
                            context.read<VehiculoProvider>();

                        if (provider.isLoading(patente)) return;
                        if (!provider.debeSincronizar(patente)) return;

                        await provider.sync(patente, vin);
                      },

                      children: [
                        ListTile(
                          title: Text(
                            "KM: ${AppFormatters.formatearKilometraje(data['KM_ACTUAL'])}",
                          ),
                        ),

                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              error,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminVehiculoFormScreen(
                                    vehiculoId: patente,
                                    datosIniciales: data,
                                  ),
                                ),
                              );
                            },
                            child: const Text("Editar"),
                          ),
                        ),

                        const SizedBox(height: 10),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}