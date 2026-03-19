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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.2),
          ),
          child: child!,
        );
      },
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
  if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") return "No cargada";
  try {
    List<String> partes = fecha.split('-');
    if (partes.length == 3) return "${partes[2]}-${partes[1]}-${partes[0]}";
    return fecha;
  } catch (e) {
    return fecha;
  }
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
      if (!mounted) return;

      if (doc.exists && doc.data()!['CLAVE'].toString() == pass) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MainPanel(
          dni: dni, 
          nombre: doc.data()!['CHOFER'] ?? "Usuario", 
          rol: doc.data()!['ROL'] ?? "USUARIO"
        )));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("DNI o Clave incorrectos")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
            keyboardType: TextInputType.number,
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
  final String dni;
  final String nombre;
  final String rol;
  const MainPanel({super.key, required this.dni, required this.nombre, required this.rol});

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
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(context, Icons.folder, "MIS DOCUMENTOS", () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => MisDocumentosScreen(dni: dni)));
          }),
          
          if (rol.toUpperCase() == "ADMIN") ...[
            const SizedBox(height: 10),
            _card(context, Icons.people, "PERSONAL", () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaPersonalScreen()));
            }),
            const SizedBox(height: 10),
            _card(context, Icons.local_shipping, "EQUIPOS", () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaEquiposScreen()));
            }),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, IconData i, String t, VoidCallback tap) {
    return Card(child: ListTile(leading: Icon(i, color: Colors.blue), title: Text(t), trailing: const Icon(Icons.arrow_forward_ios), onTap: tap));
  }
}

class MisDocumentosScreen extends StatelessWidget {
  final String dni;
  const MisDocumentosScreen({super.key, required this.dni});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mis Documentos"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).snapshots(),
        builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var user = snapshot.data!.data() as Map<String, dynamic>;
          return SingleChildScrollView(
            child: Column(
              children: [
                cabeceraFicha(user['CHOFER'], "DNI: ${formatearDNI(user['DNI'])}"),
                tituloSeccion("ESTADO DE MIS VENCIMIENTOS"),
                filaVtoSemaforo("LICENCIA DE CONDUCIR", user['LIC_COND']),
                filaVtoSemaforo("PREOCUPACIONAL (EPAP)", user['EPAP']),
                filaVtoSemaforo("CURSO MANEJO DEFENSIVO", user['CURSO_MANEJO']),
                filaVtoSemaforo("CURSO MERCANCÍAS PELIGROSAS", user['CURSO_MERCANCIAS']),
              ],
            ),
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
                var docs = snapshot.data!.docs.where((doc) => doc['CHOFER'].toString().toUpperCase().contains(_searchQuery)).toList();
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var user = docs[index].data() as Map<String, dynamic>;
                    return Card(child: ListTile(leading: const Icon(Icons.person), title: Text(user['CHOFER'] ?? "Sin Nombre"), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FichaChoferScreen(userData: user)))));
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

class ListaEquiposScreen extends StatefulWidget {
  const ListaEquiposScreen({super.key});

  @override
  State<ListaEquiposScreen> createState() => _ListaEquiposScreenState();
}

class _ListaEquiposScreenState extends State<ListaEquiposScreen> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Listado de Equipos"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.local_shipping), text: "TRACTORES"),
              Tab(icon: Icon(Icons.directions_bus_filled), text: "BATEAS"),
              Tab(icon: Icon(Icons.agriculture), text: "TOLVAS"),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Buscar por Dominio...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toUpperCase();
                  });
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildLista("TRACTOR"),
                  _buildLista("BATEA"),
                  _buildLista("TOLVA"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(String tipo) {
    return StreamBuilder(
      // Quitamos el .orderBy de aquí para evitar el error de carga infinita por falta de índices
      stream: FirebaseFirestore.instance
          .collection('VEHICULOS')
          .where('TIPO', isEqualTo: tipo)
          .snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // Filtramos y ORDENAMOS en el dispositivo para que sea más rápido y no falle
        var docs = snapshot.data!.docs.where((doc) {
          String dominio = doc['DOMINIO']?.toString().toUpperCase() ?? "";
          return dominio.contains(_searchQuery);
        }).toList();

        // Ordenamos por Dominio alfabéticamente
        docs.sort((a, b) => (a['DOMINIO'] ?? "").compareTo(b['DOMINIO'] ?? ""));

        if (docs.isEmpty) {
          return Center(child: Text("No hay unidades en $tipo", style: const TextStyle(color: Colors.grey)));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var car = docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.blue),
                title: Text(car['DOMINIO'] ?? "S/D", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${car['MARCA'] ?? ''} ${car['MODELO'] ?? ''}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (context) => FichaVehiculoScreen(carData: car))
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class FichaChoferScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  const FichaChoferScreen({super.key, required this.userData});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ficha del Personal"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(children: [
          cabeceraFicha(userData['CHOFER'], "Tractor: ${userData['TRACTOR']} | Batea: ${userData['BATEA_TOLVA']}"),
          tituloSeccion("DATOS PERSONALES"),
          filaDato(Icons.badge, "DNI", formatearDNI(userData['DNI'])),
          filaDato(Icons.fingerprint, "CUIL", formatearCUIL(userData['CUIL'])),
          filaDato(Icons.phone, "TELÉFONO", userData['TELEFONO']),
          tituloSeccion("ESTADO VENCIMIENTOS"),
          filaVtoSemaforo("(EPAP) PREOCUPACIONAL", userData['EPAP']),
          filaVtoSemaforo("(LICENCIA DE CONDUCIR)", userData['LIC_COND']),
          filaVtoSemaforo("CURSO MANEJO DEFENSIVO", userData['CURSO_MANEJO']),
        ]),
      ),
    );
  }
}

class FichaVehiculoScreen extends StatelessWidget {
  final Map<String, dynamic> carData;
  const FichaVehiculoScreen({super.key, required this.carData});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Ficha: ${carData['DOMINIO']}"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(children: [
          cabeceraFicha(carData['DOMINIO'], "${carData['MARCA']} ${carData['MODELO']}"),
          tituloSeccion("ESPECIFICACIONES"),
          filaDato(Icons.settings_suggest, "TIPO", carData['TIPO']),
          filaDato(Icons.business, "EMPRESA", carData['EMPRESA']),
          tituloSeccion("DOCUMENTACIÓN"),
          filaVtoSemaforo("VENCIMIENTO RTO", carData['VENCIMIENTO_RTO']),
          filaVtoSemaforo("VENCIMIENTO PÓLIZA", carData['VENCIMIENTO_POLIZA']),
        ]),
      ),
    );
  }
}

// --- COMPONENTES GLOBALES ---

Widget cabeceraFicha(String? t, String? s) {
  return Container(width: double.infinity, color: Colors.blue.shade900, padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t?.toUpperCase() ?? "S/D", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), Text(s ?? "", style: const TextStyle(color: Colors.white70, fontSize: 14))]));
}

Widget tituloSeccion(String texto) {
  return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), color: Colors.grey.shade200, child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)));
}

Widget filaDato(IconData i, String l, dynamic v) {
  return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Row(children: [Icon(i, size: 20, color: Colors.blue.shade800), const SizedBox(width: 15), Text(l), const Spacer(), Text(v?.toString() ?? "---", style: const TextStyle(fontWeight: FontWeight.bold))]));
}

Widget filaVtoSemaforo(String t, String? f) {
  Color c = Colors.grey;
  if (f != null && f != "---" && f != "nan" && f.isNotEmpty) {
    try {
      int dias = DateTime.parse(f).difference(DateTime.now()).inDays;
      c = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
    } catch (_) {}
  }
  return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Row(children: [Expanded(child: Text(t)), Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)), child: Text(formatearFecha(f), style: const TextStyle(color: Colors.white, fontSize: 12)))]));
}