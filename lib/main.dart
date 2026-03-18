import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LogisticaApp());
}

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Logística Coopertrans',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _subirEmpleado(BuildContext context, String nombre, String cuil, String categoria) async {
    if (nombre.isEmpty || cuil.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, completa todos los campos')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('EMPLEADOS').add({
        'nombre': nombre,
        'cuil': cuil,
        'categoria': categoria,
        'fecha_alta': DateTime.now(),
        'estado': 'Activo',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Empleado guardado con éxito')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
  }

  void _mostrarFormulario(BuildContext context) {
    String nombreLocal = '';
    String cuilLocal = '';
    String categoriaLocal = 'Chofer';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 20, left: 20, right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nuevo Legajo de Personal', 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 15),
            TextField(
              decoration: const InputDecoration(labelText: 'Nombre Completo', border: OutlineInputBorder()),
              onChanged: (val) => nombreLocal = val,
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(labelText: 'CUIL / DNI', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              onChanged: (val) => cuilLocal = val,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: categoriaLocal,
              decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
              items: ['Chofer', 'Administrativo', 'Mecánico'].map((label) => 
                DropdownMenuItem(value: label, child: Text(label))
              ).toList(),
              onChanged: (val) => categoriaLocal = val!,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR EN COOPERTRANS'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () {
                  _subirEmpleado(context, nombreLocal, cuilLocal, categoriaLocal);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coopertrans Logística'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.local_shipping, size: 50, color: Colors.blue),
          const Text('Panel de Control de Personal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const Divider(height: 30),
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('fecha_alta', descending: true).snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(doc['nombre']),
                      subtitle: Text("${doc['categoria']} - CUIL: ${doc['cuil']}"),
                      trailing: const Icon(Icons.check_circle, color: Colors.green),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormulario(context),
        label: const Text('Nuevo Empleado'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}