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
            textScaler: const TextScaler.linear(1.1),
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
    String f = fecha.replaceAll('/', '-');
    List<String> partes = f.split('-');
    if (partes.length == 3) {
      if (partes[0].length == 4) return "${partes[2]}/${partes[1]}/${partes[0]}";
      return "${partes[0]}/${partes[1]}/${partes[2]}";
    }
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(width: 300, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.local_shipping, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            TextField(
              controller: _dniController,
              keyboardType: TextInputType.number,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: "DNI", 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController,
              focusNode: _passFocus,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Clave", 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
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
      // CORRECCIÓN AQUÍ: appBar en lugar de app_bar
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
                    return Card(child: ListTile(
                      leading: const Icon(Icons.person), 
                      title: Text(user['CHOFER'] ?? "Sin Nombre"), 
                      trailing: const Icon(Icons.chevron_right), 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FichaChoferScreen(dni: user['DNI'].toString())))
                    ));
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
                decoration: InputDecoration(hintText: "Buscar por Dominio...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                onChanged: (value) => setState(() => _searchQuery = value.toUpperCase()),
              ),
            ),
            Expanded(
              child: TabBarView(children: [_buildLista("TRACTOR"), _buildLista("BATEA"), _buildLista("TOLVA")]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(String tipo) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', isEqualTo: tipo).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> vehiculosSnap) {
        if (!vehiculosSnap.hasData) return const Center(child: CircularProgressIndicator());

        return StreamBuilder(
          stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot> empleadosSnap) {
            if (!empleadosSnap.hasData) return const Center(child: CircularProgressIndicator());

            var vehiculos = vehiculosSnap.data!.docs.where((doc) {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              String dominio = data.containsKey('DOMINIO') ? data['DOMINIO'].toString().toUpperCase() : "";
              return dominio.contains(_searchQuery);
            }).toList();

            var empleados = empleadosSnap.data!.docs;

            return ListView.builder(
              itemCount: vehiculos.length,
              itemBuilder: (context, index) {
                var carDoc = vehiculos[index];
                Map<String, dynamic> carData = carDoc.data() as Map<String, dynamic>;
                String dominio = carData['DOMINIO'] ?? "S/D";

                var choferAsignado = empleados.where((e) {
                  Map<String, dynamic> empData = e.data() as Map<String, dynamic>;
                  String tractorEmp = empData.containsKey('TRACTOR') ? empData['TRACTOR'].toString() : "";
                  String bateaEmp = empData.containsKey('BATEA_TOLVA') ? empData['BATEA_TOLVA'].toString() : "";
                  return tractorEmp == dominio || bateaEmp == dominio;
                });

                bool estaLibre = choferAsignado.isEmpty;
                String nombreChofer = estaLibre ? "UNIDAD LIBRE" : (choferAsignado.first.data() as Map<String, dynamic>)['CHOFER'];

                return Card(
                  color: estaLibre ? Colors.green.shade50 : Colors.white,
                  child: ListTile(
                    leading: Icon(Icons.local_shipping, color: estaLibre ? Colors.green : Colors.blue.shade900),
                    title: Text(dominio, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Estado: $nombreChofer"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => FichaVehiculoScreen(carData: carData))
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class FichaChoferScreen extends StatefulWidget {
  final String dni;
  const FichaChoferScreen({super.key, required this.dni});
  @override
  State<FichaChoferScreen> createState() => _FichaChoferScreenState();
}

class _FichaChoferScreenState extends State<FichaChoferScreen> {
  
  void _seleccionarEquipo(String tipoFirestore, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Asignar $label"),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder(
            stream: FirebaseFirestore.instance
                .collection('VEHICULOS')
                .where('TIPO', isEqualTo: tipoFirestore == 'TRACTOR' ? 'TRACTOR' : (tipoFirestore == 'BATEA_TOLVA' ? 'BATEA' : 'TOLVA')) 
                .snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var unidades = snapshot.data!.docs;
              if (unidades.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text("No hay unidades disponibles."));

              return ListView.builder(
                shrinkWrap: true,
                itemCount: unidades.length,
                itemBuilder: (context, index) {
                  var unidad = unidades[index];
                  return ListTile(
                    title: Text(unidad['DOMINIO']),
                    subtitle: Text(unidad['MARCA'] ?? ""),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogContext);

                      await actualizarEquipoChofer(widget.dni, tipoFirestore, unidad['DOMINIO']);
                      if (!mounted) return;
                      
                      navigator.pop(); 
                      messenger.showSnackBar(const SnackBar(content: Text("Equipo actualizado")));
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ficha del Personal"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
        builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var userData = snapshot.data!.data() as Map<String, dynamic>;

          return SingleChildScrollView(
            child: Column(children: [
              Container(
                width: double.infinity,
                color: Colors.blue.shade900,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userData['CHOFER']?.toUpperCase() ?? "S/D", 
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        _botonAsignar(context, "TRACTOR", userData['TRACTOR'], () => _seleccionarEquipo('TRACTOR', 'Tractor')),
                        const SizedBox(width: 10),
                        _botonAsignar(context, "ACOPLADO", userData['BATEA_TOLVA'], () => _seleccionarEquipo('BATEA_TOLVA', 'Acoplado')),
                      ],
                    ),
                  ],
                ),
              ),
              tituloSeccion("DATOS PERSONALES"),
              filaDato(Icons.badge, "DNI", formatearDNI(userData['DNI'])),
              filaDato(Icons.fingerprint, "CUIL", formatearCUIL(userData['CUIL'])),
              filaDato(Icons.phone, "TELÉFONO", userData['TELEFONO']),
              tituloSeccion("ESTADO VENCIMIENTOS"),
              filaVtoSemaforo("(EPAP) PREOCUPACIONAL", userData['EPAP']),
              filaVtoSemaforo("(LICENCIA DE CONDUCIR)", userData['LIC_COND']),
              filaVtoSemaforo("CURSO MANEJO DEFENSIVO", userData['CURSO_MANEJO']),
            ]),
          );
        }
      ),
    );
  }

  Widget _botonAsignar(BuildContext context, String label, String? valor, VoidCallback tap) {
    return Expanded(
      child: InkWell(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white30)
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
              Text(valor == null || valor == "" ? "ASIGNAR" : valor, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class FichaVehiculoScreen extends StatefulWidget {
  final Map<String, dynamic> carData;
  const FichaVehiculoScreen({super.key, required this.carData});
  @override
  State<FichaVehiculoScreen> createState() => _FichaVehiculoScreenState();
}

class _FichaVehiculoScreenState extends State<FichaVehiculoScreen> {
  
  Future<void> _editarFecha(String campo, String label) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: "SELECCIONAR $label",
    );

    if (picked == null || !mounted) return;
    String nuevaFecha = "${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}";
    
    try {
      await FirebaseFirestore.instance.collection('VEHICULOS').doc(widget.carData['DOMINIO']).update({campo: nuevaFecha});
      if (!mounted) return;
      setState(() { widget.carData[campo] = nuevaFecha; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label actualizado")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Ficha: ${widget.carData['DOMINIO'] ?? 'S/D'}"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(
          children: [
            cabeceraFicha(widget.carData['DOMINIO'], "${widget.carData['MARCA'] ?? 'S/M'} ${widget.carData['MODELO'] ?? ''}"),
            tituloSeccion("ESPECIFICACIONES"),
            filaDato(Icons.settings_suggest, "TIPO", widget.carData['TIPO']),
            filaDato(Icons.business, "EMPRESA", widget.carData['EMPRESA']),
            tituloSeccion("DOCUMENTACIÓN (TOCAR PARA EDITAR)"),
            InkWell(onTap: () => _editarFecha('VENCIMIENTO_RTO', 'VENCIMIENTO RTO'), child: filaVtoSemaforo("VENCIMIENTO RTO", widget.carData['VENCIMIENTO_RTO'])),
            InkWell(onTap: () => _editarFecha('VENCIMIENTO_POLIZA', 'VENCIMIENTO PÓLIZA'), child: filaVtoSemaforo("VENCIMIENTO PÓLIZA", widget.carData['VENCIMIENTO_POLIZA'])),
          ],
        ),
      ),
    );
  }
}

// --- COMPONENTES GLOBALES ---

Widget cabeceraFicha(String? titulo, String? subtitulo) {
  return Container(
    width: double.infinity, color: Colors.blue.shade900, padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo?.toUpperCase() ?? "S/D", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(subtitulo ?? "", style: const TextStyle(color: Colors.white70, fontSize: 14)),
    ]),
  );
}

Widget tituloSeccion(String texto) {
  return Container(
    width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), color: Colors.grey.shade200,
    child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)),
  );
}

Widget filaDato(IconData icono, String label, dynamic valor) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: Row(children: [
      Icon(icono, size: 20, color: Colors.blue.shade800),
      const SizedBox(width: 15),
      Text(label),
      const Spacer(),
      Text(valor?.toString() ?? "---", style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );
}

Widget filaVtoSemaforo(String titulo, String? fecha) {
  Color bg = Colors.grey;
  if (fecha != null && fecha != "---" && fecha != "nan" && fecha.isNotEmpty) {
    try {
      String f = fecha.replaceAll('/', '-');
      List<String> partes = f.split('-');
      DateTime fechaVto = partes[0].length == 4 ? DateTime.parse(f) : DateTime.parse("${partes[2]}-${partes[1]}-${partes[0]}");
      int dias = fechaVto.difference(DateTime.now()).inDays;
      bg = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
    } catch (_) { bg = Colors.grey.shade400; }
  }
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    child: Row(children: [
      Expanded(child: Text(titulo)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(formatearFecha(fecha), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    ]),
  );
}

Future<void> actualizarEquipoChofer(String dni, String campo, String nuevoDominio) async {
  try {
    await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: nuevoDominio});
  } catch (e) { debugPrint("Error Firebase: $e"); }
}