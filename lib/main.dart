import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LogisticaApp());
}

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade900),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// --- FUNCIONES DE FORMATEO ---

String formatearDNI(dynamic dni) {
  String s = dni?.toString() ?? "";
  if (s.length < 7 || s.length > 8) return s;
  return s.length == 7 
      ? "${s.substring(0, 1)}.${s.substring(1, 4)}.${s.substring(4)}"
      : "${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5)}";
}

String formatearCUIL(dynamic cuil) {
  String s = cuil?.toString() ?? "";
  if (s.length != 11) return s;
  return "${s.substring(0, 2)}-${s.substring(2, 10)}-${s.substring(10)}";
}

String formatearFecha(String? fecha) {
  if (fecha == null || fecha.isEmpty || fecha == "---") return "No cargada";
  try {
    List<String> partes = fecha.split('-');
    if (partes.length == 3) return "${partes[2]}-${partes[1]}-${partes[0]}";
    return fecha;
  } catch (e) { return fecha; }
}

// --- PANTALLAS ---

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _dniController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  bool _isLoading = false;

  Future<void> _login() async {
    String dni = _dniController.text.trim();
    String pass = _passController.text.trim();
    if (dni.isEmpty || pass.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      var doc = await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).get();
      if (doc.exists && doc.data()!['CLAVE'].toString() == pass) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MainPanel(
          nombre: doc.data()!['CHOFER'] ?? "Usuario", 
          rol: doc.data()!['ROL'] ?? "USUARIO"
        )));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("DNI o Clave incorrectos")));
      }
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(width: 300, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.local_shipping, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          TextField(
            controller: _dniController,
            autofocus: true, 
            decoration: const InputDecoration(labelText: "DNI", border: OutlineInputBorder()),
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passController,
            focusNode: _passFocus,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Clave", border: OutlineInputBorder()),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 20),
          _isLoading ? const CircularProgressIndicator() : ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            onPressed: _login, 
            child: const Text("INGRESAR")
          ),
        ])),
      ),
    );
  }
}

class MainPanel extends StatelessWidget {
  final String nombre;
  final String rol;
  const MainPanel({super.key, required this.nombre, required this.rol});

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hola $nombre"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(context, Icons.folder, "MIS DOCUMENTOS", () {}),
          if (rol == "ADMIN") ...[
            const SizedBox(height: 10),
            _card(context, Icons.people, "PERSONAL", () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaPersonalScreen()));
            }),
            const SizedBox(height: 10),
            _card(context, Icons.local_shipping, "EQUIPOS", () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaEquiposScreen()));
            }),
          ]
        ],
      ),
    );
  }
  Widget _card(BuildContext context, IconData i, String t, VoidCallback tap) {
    return Card(child: ListTile(leading: Icon(i, color: Colors.blue), title: Text(t), trailing: const Icon(Icons.arrow_forward_ios), onTap: tap));
  }
}

class ListaEquiposScreen extends StatelessWidget {
  const ListaEquiposScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Listado de Equipos")),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data.containsKey('TRACTOR') && data['TRACTOR'] != null && data['TRACTOR'] != "---";
          }).toList();
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                child: ListTile(
                  leading: const Icon(Icons.local_shipping, color: Colors.blue),
                  title: Text("Tractor: ${data['TRACTOR']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Batea: ${data['BATEA_TOLVA'] ?? '---'}\nChofer: ${data['CHOFER'] ?? 'S/N'}"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ListaPersonalScreen extends StatefulWidget {
  const ListaPersonalScreen({super.key});
  @override
  State<ListaPersonalScreen> createState() => _ListaPersonalScreenState();
}

class _ListaPersonalScreenState extends State<ListaPersonalScreen> {
  String _searchQuery = "";
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Personal")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(hintText: "Buscar chofer...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              onChanged: (value) => setState(() => _searchQuery = value.toUpperCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('CHOFER').snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snapshot.data!.docs.where((doc) {
                  return doc['CHOFER'].toString().toUpperCase().contains(_searchQuery);
                }).toList();
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var user = docs[index].data() as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(user['CHOFER'] ?? "Sin Nombre"),
                        subtitle: Text("DNI: ${formatearDNI(user['DNI'])}"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FichaChoferScreen(userData: user))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- FICHA DEL CHOFER (DISEÑO FINAL COMPACTO) ---
class FichaChoferScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  const FichaChoferScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final String nombre = userData['CHOFER'] ?? "Detalles";
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ficha del Personal"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        toolbarHeight: 40,
      ),
      body: SingleChildScrollView( // Usamos SingleChildScrollView con Column para control total
        child: Column(
          mainAxisSize: MainAxisSize.min, // LA CLAVE: Ocupa lo mínimo necesario
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CABECERA
            Container(
              width: double.infinity,
              color: Colors.blue.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _datoHeaderCompacto("TRACTOR", userData['TRACTOR']),
                      const SizedBox(width: 40),
                      _datoHeaderCompacto("BATEA", userData['BATEA_TOLVA']),
                    ],
                  ),
                ],
              ),
            ),

            _tituloSeccion("DATOS PERSONALES"),
            _filaDatoMinima(Icons.badge, "DNI", formatearDNI(userData['DNI'])),
            _filaDatoMinima(Icons.fingerprint, "CUIL", formatearCUIL(userData['CUIL'])),
            _filaDatoMinima(Icons.phone, "TELEFONO", userData['TELEFONO']),
            _filaDatoMinima(Icons.business, "EMPRESA", userData['EMPRESA']),
            
            _tituloSeccion("ESTADO VENCIMIENTOS"),
            _filaVtoSemaforoCompacta("(EPAP) PREOCUPACIONAL", userData['EPAP']),
            _filaVtoSemaforoCompacta("(LICENCIA DE CONDUCIR)", userData['LIC_COND']),
            _filaVtoSemaforoCompacta("CURSO DE MANEJO DEFENSIVO", userData['CURSO_MANEJO']),
            _filaVtoSemaforoCompacta("CURSO DE MERCANCIAS PELIGROSAS", userData['CURSO_MERCANCIAS']),
          ],
        ),
      ),
    );
  }

  Widget _tituloSeccion(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.grey.shade200,
      child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 9)),
    );
  }

  Widget _datoHeaderCompacto(String label, dynamic valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white70)),
        Text(valor?.toString() ?? "---", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
      ],
    );
  }

  Widget _filaDatoMinima(IconData icono, String label, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), // ESPACIO MÍNIMO
      child: Row(
        children: [
          Icon(icono, size: 12, color: Colors.blue.shade800),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const Spacer(),
          Text(valor?.toString() ?? "---", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _filaVtoSemaforoCompacta(String titulo, String? fecha) {
    Color bgStatus = Colors.grey.shade400; 

    if (fecha != null && fecha.isNotEmpty && fecha != "---") {
      try {
        DateTime hoy = DateTime.now();
        DateTime vto = DateTime.parse(fecha);
        int diasDiferencia = vto.difference(hoy).inDays;

        if (diasDiferencia < 0) {
          bgStatus = Colors.red.shade600; 
        } else if (diasDiferencia <= 30) {
          bgStatus = Colors.orange.shade400; 
        } else {
          bgStatus = Colors.green.shade600; 
        }
      } catch (e) {
        bgStatus = Colors.grey.shade400;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), // CASI SIN ESPACIO
      child: Row(
        children: [
          Expanded(
            child: Text(titulo, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: bgStatus, borderRadius: BorderRadius.circular(2)),
            child: Text(
              formatearFecha(fecha), 
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)
            ),
          ),
        ],
      ),
    );
  }
}