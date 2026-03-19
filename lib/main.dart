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

// --- CONSTANTES ---
const List<String> empresasDisponibles = [
  "VECCHI ARIEL Y VECCHI GRACIELA S.R.L (30-70910015-3)",
  "SUCESIÓN DE VECCHI CARLOS LUIS (20-08569424-4)"
];

// --- FUNCIONES DE FORMATEO ---

String formatearDNI(dynamic dni) {
  final String s = dni?.toString() ?? "";
  if (s.length < 7 || s.length > 8) return s;
  return s.length == 7 
      ? "${s.substring(0, 1)}.${s.substring(1, 4)}.${s.substring(4)}"
      : "${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5)}";
}

String formatearCUIL(dynamic cuil) {
  final String s = cuil?.toString() ?? "";
  if (s.length != 11) return s;
  return "${s.substring(0, 2)}-${s.substring(2, 10)}-${s.substring(10)}";
}

String formatearFecha(String? fecha) {
  if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") return "Sin datos";
  try {
    final String f = fecha.replaceAll('/', '-');
    final List<String> partes = f.split('-');
    if (partes.length == 3) {
      if (partes[0].length == 4) return "${partes[2]}/${partes[1]}/${partes[0]}";
      return "${partes[0]}/${partes[1]}/${partes[2]}";
    }
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
    final String dni = _dniController.text.trim();
    final String pass = _passController.text.trim();
    if (dni.isEmpty || pass.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).get();
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
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "DNI", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController,
              focusNode: _passFocus,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Clave", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
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
      appBar: AppBar(
        title: Text("Hola $nombre"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(context, Icons.folder, "MIS DOCUMENTOS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => MisDocumentosScreen(dni: dni)))),
          if (rol.toUpperCase() == "ADMIN") ...[
            const SizedBox(height: 10),
            _card(context, Icons.people, "PERSONAL", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaPersonalScreen()))),
            const SizedBox(height: 10),
            _card(context, Icons.local_shipping, "EQUIPOS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaEquiposScreen()))),
            const SizedBox(height: 10),
            // --- NUEVO BOTÓN DE VENCIMIENTOS ---
            _card(context, Icons.notification_important, "CONTROL VENCIMIENTOS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PanelVencimientosScreen()))),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, IconData i, String t, VoidCallback tap) {
    return Card(child: ListTile(leading: Icon(i, color: Colors.blue), title: Text(t), trailing: const Icon(Icons.arrow_forward_ios), onTap: tap));
  }
}

// --- PANTALLA DE CONTROL DE VENCIMIENTOS ---

class PanelVencimientosScreen extends StatelessWidget {
  const PanelVencimientosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Vencimientos Globales"),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.person), text: "PERSONAL"),
              Tab(icon: Icon(Icons.local_shipping), text: "EQUIPOS"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ListaVencimientosGenerica(coleccion: 'EMPLEADOS', nombreCampo: 'CHOFER'),
            _ListaVencimientosGenerica(coleccion: 'VEHICULOS', nombreCampo: 'DOMINIO'),
          ],
        ),
      ),
    );
  }
}

class _ListaVencimientosGenerica extends StatelessWidget {
  final String coleccion;
  final String nombreCampo;
  const _ListaVencimientosGenerica({required this.coleccion, required this.nombreCampo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection(coleccion).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        List<Map<String, dynamic>> alertas = [];

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final nombreSujeto = data[nombreCampo] ?? "Sin nombre";

          data.forEach((key, value) {
            // Buscamos campos de fecha
            if (key.contains("VENCIMIENTO") || key == "EPAP" || key == "LIC_COND" || key == "CURSO_MANEJO" || key == "CURSO_MERCANCIAS") {
              if (value != null && value.toString().isNotEmpty && value != "---" && value != "nan") {
                int dias = _obtenerDiasRestantes(value.toString());
                if (dias <= 45) { // Mostramos si faltan 45 días o menos
                  alertas.add({
                    'sujeto': nombreSujeto,
                    'documento': key.replaceAll('VENCIMIENTO_', '').replaceAll('_', ' '),
                    'fecha': value,
                    'dias': dias,
                  });
                }
              }
            }
          });
        }

        alertas.sort((a, b) => a['dias'].compareTo(b['dias']));

        if (alertas.isEmpty) return const Center(child: Text("No hay vencimientos próximos"));

        return ListView.builder(
          itemCount: alertas.length,
          itemBuilder: (context, index) {
            final al = alertas[index];
            final bool vencido = al['dias'] < 0;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: Icon(Icons.warning, color: vencido ? Colors.red : Colors.orange),
                title: Text(al['sujeto']),
                subtitle: Text("${al['documento']}: ${formatearFecha(al['fecha'])}"),
                trailing: Text(
                  vencido ? "VENCIDO" : "EN ${al['dias']} DÍAS",
                  style: TextStyle(color: vencido ? Colors.red : Colors.orange, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int _obtenerDiasRestantes(String fecha) {
    try {
      final String f = fecha.replaceAll('/', '-');
      final List<String> partes = f.split('-');
      DateTime fVto;
      if (partes[0].length == 4) {
        fVto = DateTime.parse(f);
      } else {
        fVto = DateTime.parse("${partes[2]}-${partes[1].padLeft(2,'0')}-${partes[0].padLeft(2,'0')}");
      }
      return fVto.difference(DateTime.now()).inDays;
    } catch (_) { return 999; }
  }
}

// --- RESTO DE PANTALLAS (PERSONAL Y EQUIPOS) ---

class ListaPersonalScreen extends StatefulWidget {
  const ListaPersonalScreen({super.key});
  @override
  State<ListaPersonalScreen> createState() => _ListaPersonalScreenState();
}

class _ListaPersonalScreenState extends State<ListaPersonalScreen> {
  String _searchQuery = "";

  void _dialogNuevoChofer() {
    final nCtrl = TextEditingController();
    final dCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nuevo Chofer"),
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            TextField(controller: nCtrl, decoration: const InputDecoration(labelText: "Nombre Completo"), textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 10), 
            TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "DNI"), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () async {
            if (dCtrl.text.isEmpty) return;
            final nav = Navigator.of(ctx);
            await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dCtrl.text.trim()).set({
              'CHOFER': nCtrl.text.toUpperCase(),
              'DNI': dCtrl.text.trim(),
              'CLAVE': dCtrl.text.trim(),
              'ROL': 'USUARIO'
            });
            if (!ctx.mounted) return;
            nav.pop();
          }, child: const Text("Guardar"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Personal")),
      floatingActionButton: FloatingActionButton(onPressed: _dialogNuevoChofer, child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: InputDecoration(hintText: "Buscar chofer...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), onChanged: (v) => setState(() => _searchQuery = v.toUpperCase()))),
        Expanded(
          child: StreamBuilder(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('CHOFER').snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs.where((doc) => doc['CHOFER'].toString().toUpperCase().contains(_searchQuery)).toList();
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) => Card(child: ListTile(leading: const Icon(Icons.person), title: Text(docs[index]['CHOFER'] ?? "Sin Nombre"), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FichaChoferScreen(dni: docs[index].id))))),
              );
            },
          ),
        ),
      ]),
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
  
  Future<void> _editarCampoTexto(String campo, String etiqueta, String valorActual) async {
    final ctrl = TextEditingController(text: valorActual == "Sin datos" ? "" : valorActual);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Editar $etiqueta"),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: "Ingrese $etiqueta"),
          textCapitalization: TextCapitalization.characters,
          keyboardType: campo == 'TELEFONO' || campo == 'CUIL' ? TextInputType.number : TextInputType.text,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({
                campo: ctrl.text.trim().toUpperCase()
              });
              if (!ctx.mounted) return;
              nav.pop();
            }, 
            child: const Text("Guardar")
          ),
        ],
      ),
    );
  }

  void _seleccionarEmpresa(String coleccion, String idDoc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Seleccionar Empresa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresasDisponibles.map((emp) => ListTile(
            title: Text(emp),
            onTap: () async {
              final nav = Navigator.of(ctx);
              await FirebaseFirestore.instance.collection(coleccion).doc(idDoc).update({'EMPRESA': emp});
              if (!ctx.mounted) return;
              nav.pop();
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _editarFecha(String campo, String label) async {
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: DateTime.now(), 
      firstDate: DateTime(2020), 
      lastDate: DateTime(2035)
    );
    if (picked == null || !mounted) return;
    final String nueva = "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}";
    await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({campo: nueva});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label actualizado")));
  }

  void _seleccionarEquipo(String tipoFirestore, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Asignar $label"),
        content: SizedBox(width: double.maxFinite, child: StreamBuilder(
          stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', isEqualTo: tipoFirestore == 'TRACTOR' ? 'TRACTOR' : (tipoFirestore == 'BATEA_TOLVA' ? 'BATEA' : 'TOLVA')).snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final unidades = snapshot.data!.docs;
            return ListView.builder(shrinkWrap: true, itemCount: unidades.length, itemBuilder: (context, index) => ListTile(title: Text(unidades[index]['DOMINIO']), onTap: () async {
              final nav = Navigator.of(dialogContext);
              await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({tipoFirestore: unidades[index]['DOMINIO']});
              if (!dialogContext.mounted) return;
              nav.pop();
            }));
          },
        )),
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
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          final u = snapshot.data!.data() as Map<String, dynamic>;
          return SingleChildScrollView(
            child: Column(children: [
              Container(width: double.infinity, color: Colors.blue.shade900, padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u['CHOFER']?.toUpperCase() ?? "S/D", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Row(children: [
                  _botonAsignar("TRACTOR", u['TRACTOR'], () => _seleccionarEquipo('TRACTOR', 'Tractor')),
                  const SizedBox(width: 10),
                  _botonAsignar("ACOPLADO", u['BATEA_TOLVA'], () => _seleccionarEquipo('BATEA_TOLVA', 'Acoplado')),
                ]),
              ])),
              tituloSeccion("DATOS PERSONALES (TOCAR PARA EDITAR)"),
              filaDato(Icons.badge, "DNI", formatearDNI(u['DNI'])),
              InkWell(onTap: () => _editarCampoTexto('CUIL', 'CUIL', u['CUIL']?.toString() ?? ""), child: filaDato(Icons.fingerprint, "CUIL", formatearCUIL(u['CUIL'] ?? "---"))),
              InkWell(onTap: () => _editarCampoTexto('TELEFONO', 'TELÉFONO', u['TELEFONO']?.toString() ?? ""), child: filaDato(Icons.phone, "TELÉFONO", u['TELEFONO'] ?? "Sin datos")),
              InkWell(onTap: () => _seleccionarEmpresa('EMPLEADOS', widget.dni), child: filaDato(Icons.business, "EMPRESA", u['EMPRESA'] ?? "Sin datos")),
              tituloSeccion("VENCIMIENTOS (TOCAR PARA EDITAR)"),
              InkWell(onTap: () => _editarFecha('EPAP', 'EPAP'), child: filaVtoSemaforo("(EPAP) PREOCUPACIONAL", u['EPAP'])),
              InkWell(onTap: () => _editarFecha('LIC_COND', 'LICENCIA'), child: filaVtoSemaforo("(LICENCIA DE CONDUCIR)", u['LIC_COND'])),
              InkWell(onTap: () => _editarFecha('CURSO_MANEJO', 'CURSO MANEJO'), child: filaVtoSemaforo("CURSO MANEJO DEFENSIVO", u['CURSO_MANEJO'])),
              InkWell(onTap: () => _editarFecha('CURSO_MERCANCIAS', 'MERCANCIAS'), child: filaVtoSemaforo("CURSO MERCANCÍAS PELIGROSAS", u['CURSO_MERCANCIAS'])),
            ]),
          );
        },
      ),
    );
  }

  Widget _botonAsignar(String label, String? valor, VoidCallback tap) {
    return Expanded(child: InkWell(onTap: tap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withAlpha(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white30)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      Text(valor == null || valor == "" ? "ASIGNAR" : valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    ]))));
  }
}

// --- EQUIPOS ---

class ListaEquiposScreen extends StatefulWidget {
  const ListaEquiposScreen({super.key});
  @override
  State<ListaEquiposScreen> createState() => _ListaEquiposScreenState();
}

class _ListaEquiposScreenState extends State<ListaEquiposScreen> {
  String _searchQuery = "";

  void _dialogNuevoEquipo() {
    final dCtrl = TextEditingController();
    String tipoSel = 'TRACTOR';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setSt) => AlertDialog(
        title: const Text("Nuevo Equipo"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "Dominio"), textCapitalization: TextCapitalization.characters),
          DropdownButton<String>(value: tipoSel, isExpanded: true, items: ['TRACTOR', 'BATEA', 'TOLVA'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) => setSt(() => tipoSel = v!)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () async {
            if (dCtrl.text.isEmpty) return;
            final nav = Navigator.of(ctx);
            await FirebaseFirestore.instance.collection('VEHICULOS').doc(dCtrl.text.toUpperCase().trim()).set({'DOMINIO': dCtrl.text.toUpperCase().trim(), 'TIPO': tipoSel});
            if (!ctx.mounted) return;
            nav.pop();
          }, child: const Text("Guardar"))
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Equipos"), 
          bottom: const TabBar(tabs: [Tab(text: "TRACTORES"), Tab(text: "BATEAS"), Tab(text: "TOLVAS")]),
        ),
        floatingActionButton: FloatingActionButton(onPressed: _dialogNuevoEquipo, child: const Icon(Icons.add)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Buscar dominio...", 
                  prefixIcon: const Icon(Icons.search), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                ), 
                onChanged: (v) => setState(() => _searchQuery = v.toUpperCase())
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _buildLista("TRACTOR"), 
                _buildLista("BATEA"), 
                _buildLista("TOLVA")
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(String tipo) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', isEqualTo: tipo).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.where((d) => d['DOMINIO'].toString().contains(_searchQuery)).toList();
        return ListView.builder(
          itemCount: docs.length, 
          itemBuilder: (context, index) => Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping), 
              title: Text(docs[index]['DOMINIO']), 
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (context) => FichaVehiculoScreen(carData: docs[index].data() as Map<String, dynamic>)
              ))
            )
          )
        );
      },
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
  
  Future<void> _editarFecha(String campo) async {
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: DateTime.now(), 
      firstDate: DateTime(2020), 
      lastDate: DateTime(2035)
    );
    if (picked != null && mounted) {
      final String nueva = "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}";
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(widget.carData['DOMINIO'])
          .update({campo: nueva});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Ficha: ${widget.carData['DOMINIO']}"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(widget.carData['DOMINIO']).snapshots(),
        builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          
          final v = snapshot.data!.data() as Map<String, dynamic>;
          
          return SingleChildScrollView(
            child: Column(
              children: [
                cabeceraFicha(v['DOMINIO'], v['TIPO']),
                
                tituloSeccion("FICHA TÉCNICA"),
                
                filaDato(Icons.branding_watermark, "MARCA", v['MARCA']?.toString() ?? "Sin datos"),
                filaDato(Icons.directions_car, "MODELO", v['MODELO']?.toString() ?? "Sin datos"),
                filaDato(Icons.calendar_today, "AÑO", v['AÑO']?.toString() ?? "Sin datos"),
                filaDato(Icons.settings, "TIPIFICACIÓN", v['TIPIFICADA']?.toString() ?? "Sin datos"),
                filaDato(Icons.business, "EMPRESA", v['EMPRESA']?.toString() ?? "Sin datos"),
                
                tituloSeccion("DOCUMENTACIÓN (TOCAR PARA ACTUALIZAR)"),
                
                InkWell(
                  onTap: () => _editarFecha('VENCIMIENTO_RTO'), 
                  child: filaVtoSemaforo("VENCIMIENTO RTO", v['VENCIMIENTO_RTO'])
                ),
                
                InkWell(
                  onTap: () => _editarFecha('VENCIMIENTO_POLIZA'), 
                  child: filaVtoSemaforo("VENCIMIENTO PÓLIZA", v['VENCIMIENTO_POLIZA'])
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- COMPONENTES GLOBALES ---

Widget cabeceraFicha(String? titulo, String? subtitulo) {
  return Container(width: double.infinity, color: Colors.blue.shade900, padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(titulo?.toUpperCase() ?? "S/D", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
    Text(subtitulo ?? "", style: const TextStyle(color: Colors.white70, fontSize: 14)),
  ]));
}

Widget tituloSeccion(String texto) {
  return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), color: Colors.grey.shade200, child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)));
}

Widget filaDato(IconData icono, String label, dynamic valor) {
  return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Row(children: [Icon(icono, size: 20, color: Colors.blue.shade800), const SizedBox(width: 15), Text(label), const Spacer(), Text(valor?.toString() ?? "---", style: const TextStyle(fontWeight: FontWeight.bold))]));
}

Widget filaVtoSemaforo(String titulo, String? fecha) {
  Color bg = Colors.grey;
  if (fecha != null && fecha != "---" && fecha != "nan" && fecha.isNotEmpty) {
    try {
      final String f = fecha.replaceAll('/', '-');
      final List<String> partes = f.split('-');
      DateTime fechaVto;
      if (partes[0].length == 4) {
        fechaVto = DateTime.parse(f);
      } else {
        fechaVto = DateTime.parse("${partes[2]}-${partes[1].padLeft(2,'0')}-${partes[0].padLeft(2,'0')}");
      }
      final int dias = fechaVto.difference(DateTime.now()).inDays;
      bg = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
    } catch (_) { bg = Colors.grey.shade400; }
  }
  return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Row(children: [
    Expanded(child: Text(titulo)),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)), child: Text(formatearFecha(fecha), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
  ]));
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
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          final user = snapshot.data!.data() as Map<String, dynamic>;
          return Column(children: [
            cabeceraFicha(user['CHOFER'], "DNI: ${formatearDNI(user['DNI'])}"),
            tituloSeccion("ESTADO DE MIS VENCIMIENTOS"),
            filaVtoSemaforo("LICENCIA DE CONDUCIR", user['LIC_COND']),
            filaVtoSemaforo("PREOCUPACIONAL (EPAP)", user['EPAP']),
            filaVtoSemaforo("CURSO MANEJO DEFENSIVO", user['CURSO_MANEJO']),
            filaVtoSemaforo("CURSO MERCANCÍAS PELIGROSAS", user['CURSO_MERCANCIAS']),
          ]);
        },
      ),
    );
  }
}