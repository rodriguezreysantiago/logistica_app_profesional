import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPersonalListaScreen extends StatefulWidget {
  const AdminPersonalListaScreen({super.key});

  @override
  State<AdminPersonalListaScreen> createState() => _AdminPersonalListaScreenState();
}

class _AdminPersonalListaScreenState extends State<AdminPersonalListaScreen> {
  // Controlador para el buscador
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    // Escuchamos los cambios en el buscador
    _searchController.addListener(() {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión de Personal"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Buscar por nombre...",
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // ✅ ORDEN ALFABÉTICO: Usamos orderBy por el campo 'CHOFER'
        stream: FirebaseFirestore.instance
            .collection('EMPLEADOS')
            .orderBy('CHOFER') 
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error al cargar datos"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Filtramos la lista localmente basándonos en el buscador
          final empleados = snapshot.data!.docs.where((doc) {
            final nombre = (doc['CHOFER'] as String? ?? '').toUpperCase();
            return nombre.contains(_searchText);
          }).toList();

          if (empleados.isEmpty) {
            return const Center(child: Text("No se encontraron coincidencias"));
          }

          return ListView.builder(
            itemCount: empleados.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              var data = empleados[index].data() as Map<String, dynamic>;
              
              return Card(
                elevation: 2,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF1A3A5A),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    data['CHOFER'] ?? 'Sin nombre',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("DNI: ${data['DNI'] ?? 'N/A'}"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Acción al tocar un chofer
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}