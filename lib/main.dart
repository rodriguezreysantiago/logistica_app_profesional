import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart'; 
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'), 
      ],
      locale: const Locale('es', 'AR'), 
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

// --- FUNCIONES DE LÓGICA ---

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

int _calcularDiasRestantes(String? fecha) {
  if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") return 999;
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

// --- GESTIÓN DE IMÁGENES ---

Future<void> _subirSolicitudImagen(BuildContext context, {
  required String idSujeto, 
  required String nombreSujeto, 
  required String documentoEtiqueta, 
  required String campoFirestore,
  required String coleccionDestino,
}) async {
  // 1. PRIMERO: SELECCIONAR LA NUEVA FECHA
  final DateTime? nuevaFecha = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime(2024),
    lastDate: DateTime(2035),
    helpText: "PASO 1: SELECCIONE EL VENCIMIENTO",
  );

  if (nuevaFecha == null || !context.mounted) return;
  final String fechaString = "${nuevaFecha.year}-${nuevaFecha.month.toString().padLeft(2,'0')}-${nuevaFecha.day.toString().padLeft(2,'0')}";

  // 2. SEGUNDO: MENÚ PARA ADJUNTAR RESPALDO
  final ImagePicker picker = ImagePicker();
  final XFile? image = await showModalBottomSheet<XFile>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("PASO 2: ADJUNTAR COMPROBANTE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.blue), 
            title: const Text('Tomar Foto'), 
            onTap: () async {
              final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);
              if (ctx.mounted) Navigator.pop(ctx, img);
            }
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.green), 
            title: const Text('Elegir de Galería'), 
            onTap: () async {
              final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
              if (ctx.mounted) Navigator.pop(ctx, img);
            }
          ),
          ListTile(
            leading: const Icon(Icons.close), 
            title: const Text('Cancelar'), 
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      ),
    ),
  );

  if (image == null || !context.mounted) return;

  // 3. TERCERO: PROCESO DE SUBIDA
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(), 
          SizedBox(width: 20), 
          Text("Enviando revisión...")
        ]
      )
    ),
  );

  try {
    File file = File(image.path);
    String fileName = "solicitud_${campoFirestore}_${DateTime.now().millisecondsSinceEpoch}.jpg";
    Reference ref = FirebaseStorage.instance.ref().child('solicitudes').child(fileName);

    UploadTask uploadTask = ref.putFile(file);
    TaskSnapshot snapshot = await uploadTask;
    String url = await snapshot.ref.getDownloadURL();

    // Guardamos la solicitud para que el admin la apruebe
    await FirebaseFirestore.instance.collection('SOLICITUDES').add({
      'ID_SUJETO': idSujeto,
      'NOMBRE_SUJETO': nombreSujeto,
      'DOCUMENTO': documentoEtiqueta,
      'CAMPO_FIRESTORE': campoFirestore,
      'COLECCION_DESTINO': coleccionDestino,
      'NUEVA_FECHA': fechaString,
      'URL_FOTO': url,
      'ESTADO': 'PENDIENTE',
      'FECHA_PEDIDO': DateTime.now(),
    });

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Cerrar loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Solicitud enviada. El administrador la revisará pronto."))
    );

  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error al enviar: $e"), backgroundColor: Colors.red)
    );
  }
}

Future<void> _subirImagenDirectaAdmin(BuildContext context, String idSujeto, String campoFirestore, String coleccionDestino) async {
  final ImagePicker picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);

  if (image == null || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Actualizando imagen...")])),
  );

  try {
    File file = File(image.path);
    String fileName = "admin_update_${idSujeto}_${DateTime.now().millisecondsSinceEpoch}.jpg";
    Reference ref = FirebaseStorage.instance.ref().child('documentos').child(fileName);

    await ref.putFile(file);
    String url = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection(coleccionDestino).doc(idSujeto).update({
      'FOTO_$campoFirestore': url,
    });

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imagen actualizada con éxito")));
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al actualizar: $e"), backgroundColor: Colors.red));
    }
  }
}

Future<void> _confirmarEliminarImagen(BuildContext context, String col, String id, String campo, String url) async {
  bool? confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("¿Eliminar imagen?"),
      content: const Text("Esta acción borrará la foto permanentemente de la base de datos."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
      ],
    ),
  );

  if (confirmar == true) {
    try {
      await FirebaseFirestore.instance.collection(col).doc(id).update({
        'FOTO_$campo': FieldValue.delete(),
      });
      
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imagen eliminada")));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
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

class PanelVencimientosScreen extends StatelessWidget {
  const PanelVencimientosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Vencimientos"),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: "PERSONAL"),
              Tab(text: "EQUIPOS"),
              Tab(icon: Icon(Icons.camera_alt), text: "SOLICITUDES"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _ListaVencimientosGenerica(coleccion: 'EMPLEADOS', nombreCampo: 'CHOFER'),
            const _ListaVencimientosGenerica(coleccion: 'VEHICULOS', nombreCampo: 'DOMINIO'),
            _SeccionSolicitudesPendientesAdmin(),
          ],
        ),
      ),
    );
  }
}

class _SeccionSolicitudesPendientesAdmin extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('SOLICITUDES').where('ESTADO', isEqualTo: 'PENDIENTE').snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty) return const Center(child: Text("No hay fotos pendientes de revisión"));

        return ListView.builder(
          itemCount: solicitudes.length,
          itemBuilder: (context, index) {
            final sol = solicitudes[index];
            return Card(
              margin: const EdgeInsets.all(10),
              child: ListTile(
                leading: InkWell(
                  onTap: () => _verFotoGrande(context, sol['DOCUMENTO'], sol['URL_FOTO']),
                  child: Image.network(sol['URL_FOTO'], width: 50, height: 50, fit: BoxFit.cover),
                ),
                title: Text("${sol['NOMBRE_SUJETO']}"),
                subtitle: Text("Documento: ${sol['DOCUMENTO']}\nNuevo Vto: ${formatearFecha(sol['NUEVA_FECHA'])}"),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _aprobarSolicitud(context, sol)),
                    IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => _rechazarSolicitud(context, sol)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _verFotoGrande(BuildContext context, String titulo, String url) {
    showDialog(context: context, builder: (_) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AppBar(title: Text(titulo), automaticallyImplyLeading: false, actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]),
      InteractiveViewer(child: Image.network(url)),
    ])));
  }

  Future<void> _aprobarSolicitud(BuildContext context, DocumentSnapshot sol) async {
    try {
      await FirebaseFirestore.instance.collection(sol['COLECCION_DESTINO']).doc(sol['ID_SUJETO']).update({
        sol['CAMPO_FIRESTORE']: sol['NUEVA_FECHA'],
        'FOTO_${sol['CAMPO_FIRESTORE']}': sol['URL_FOTO']
      });
      await sol.reference.update({'ESTADO': 'APROBADO'});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vencimiento actualizado correctamente")));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _rechazarSolicitud(BuildContext context, DocumentSnapshot sol) async {
    await sol.reference.update({'ESTADO': 'RECHAZADO'});
  }
}

class _ListaVencimientosGenerica extends StatelessWidget {
  final String coleccion;
  final String nombreCampo;
  const _ListaVencimientosGenerica({required this.coleccion, required this.nombreCampo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: FirebaseFirestore.instance.collection(coleccion).get(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error de conexión"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        List<Map<String, dynamic>> alertas = [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final nombreSujeto = data[nombreCampo] ?? "Sin nombre";

          data.forEach((key, value) {
            if (key.contains("VENCIMIENTO") || key == "EPAP" || key == "LIC_COND" || key == "CURSO_MANEJO" || key == "CURSO_MERCANCIAS") {
              if (value != null && value.toString().isNotEmpty && value != "---" && value != "nan") {
                int dias = _calcularDiasRestantes(value.toString());
                if (dias <= 45) {
                  alertas.add({
                    'sujeto': nombreSujeto,
                    'documento': key.replaceAll('VENCIMIENTO_', '').replaceAll('_', ' '),
                    'fecha': value,
                    'dias': dias,
                    'id': doc.id,
                    'dataFull': data,
                  });
                }
              }
            }
          });
        }

        alertas.sort((a, b) => a['dias'].compareTo(b['dias']));
        if (alertas.isEmpty) return const Center(child: Text("Sin vencimientos próximos (45 días)"));

        return ListView.builder(
          itemCount: alertas.length,
          itemBuilder: (context, index) {
            final al = alertas[index];
            final bool vencido = al['dias'] < 0;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: Icon(Icons.warning, color: vencido ? Colors.red : (al['dias'] <= 15 ? Colors.orange : Colors.amber)),
                title: Text(al['sujeto']),
                subtitle: Text("${al['documento']}: ${formatearFecha(al['fecha'])}"),
                trailing: Text(
                  vencido ? "VENCIDO" : "EN ${al['dias']} DÍAS",
                  style: TextStyle(color: vencido ? Colors.red : Colors.orange, fontWeight: FontWeight.bold),
                ),
                onTap: () {
                   if(coleccion == 'EMPLEADOS') {
                     Navigator.push(context, MaterialPageRoute(builder: (context) => FichaChoferScreen(dni: al['id'])));
                   } else {
                     Navigator.push(context, MaterialPageRoute(builder: (context) => FichaVehiculoScreen(carData: al['dataFull'])));
                   }
                },
              ),
            );
          },
        );
      },
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

void _dialogNuevoChofer() {
  final nCtrl = TextEditingController();
  final dCtrl = TextEditingController();
  final cuilCtrl = TextEditingController();
  final telCtrl = TextEditingController();
  
  String empresaSel = empresasDisponibles.first; 

  // Variables para Fechas
  String? fechaPreo, fechaLic, fechaManejo, fechaCargas;
  // Variables para los archivos de imagen locales
  File? filePreo, fileLic, fileManejo, fileCargas;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSt) => AlertDialog(
        title: const Text("Nuevo Personal", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nCtrl, decoration: const InputDecoration(labelText: "Nombre Completo"), textCapitalization: TextCapitalization.characters),
                TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "DNI (Obligatorio) *"), keyboardType: TextInputType.number),
                TextField(controller: cuilCtrl, decoration: const InputDecoration(labelText: "CUIL"), keyboardType: TextInputType.number),
                TextField(controller: telCtrl, decoration: const InputDecoration(labelText: "Teléfono"), keyboardType: TextInputType.phone),
                
                const SizedBox(height: 20),
                const Align(alignment: Alignment.centerLeft, child: Text("Empresa:", style: TextStyle(fontSize: 12, color: Colors.grey))),
                DropdownButton<String>(
                  value: empresaSel,
                  isExpanded: true,
                  items: empresasDisponibles.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
                  onChanged: (v) => setSt(() => empresaSel = v!),
                ),
                
                const Divider(height: 40),
                const Text("Vencimientos y Fotos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 10),

                // ITEMS CON FECHA Y CÁMARA
                _itemCompletoDialog(context, "Preocupacional (EPAP)", fechaPreo, filePreo, 
                  onFecha: (f) => setSt(() => fechaPreo = f), 
                  onFoto: (file) => setSt(() => filePreo = file)),
                
                _itemCompletoDialog(context, "Licencia de Conducir", fechaLic, fileLic, 
                  onFecha: (f) => setSt(() => fechaLic = f), 
                  onFoto: (file) => setSt(() => fileLic = file)),
                
                _itemCompletoDialog(context, "Manejo Defensivo", fechaManejo, fileManejo, 
                  onFecha: (f) => setSt(() => fechaManejo = f), 
                  onFoto: (file) => setSt(() => fileManejo = file)),
                
                _itemCompletoDialog(context, "Mercancías Peligrosas", fechaCargas, fileCargas, 
                  onFecha: (f) => setSt(() => fechaCargas = f), 
                  onFoto: (file) => setSt(() => fileCargas = file)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () async {
              if (dCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("El DNI es obligatorio")));
                return;
              }

              // Mostrar indicador de carga
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

              try {
                final String dni = dCtrl.text.trim();
                
                // Función interna para subir imagen si existe
                Future<String> subir(File? f, String nombreDoc) async {
                  if (f == null) return '---';
                  final ref = FirebaseStorage.instance.ref().child('CHOFERES/$dni/$nombreDoc.jpg');
                  await ref.putFile(f);
                  return await ref.getDownloadURL();
                }

                // Subir todas las fotos en paralelo
                String urlP = await subir(filePreo, 'EPAP');
                String urlL = await subir(fileLic, 'LICENCIA');
                String urlM = await subir(fileManejo, 'MANEJO');
                String urlC = await subir(fileCargas, 'CARGAS');

                await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).set({
                  'CHOFER': nCtrl.text.toUpperCase().trim(),
                  'DNI': dni,
                  'CUIL': cuilCtrl.text.trim(),
                  'TELEFONO': telCtrl.text.trim(),
                  'EMPRESA': empresaSel,
                  'CLAVE': dni,
                  'ROL': 'USUARIO',
                  'ESTADO': 'ACTIVO',
                  'VTO_EPAP': fechaPreo ?? '---',
                  'VTO_LICENCIA': fechaLic ?? '---',
                  'VTO_MANEJO': fechaManejo ?? '---',
                  'VTO_CARGAS': fechaCargas ?? '---',
                  'URL_EPAP': urlP,
                  'URL_LICENCIA': urlL,
                  'URL_MANEJO': urlM,
                  'URL_CARGAS': urlC,
                });
                if (!context.mounted) return; // Verifica que la pantalla siga activa
                Navigator.pop(context); // Cierra el loading
                Navigator.pop(ctx);    // Cierra el alta
                Navigator.pop(context); // Cierra el loading
                Navigator.pop(ctx);    // Cierra el alta
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al subir: $e")));
              }
            }, 
            child: const Text("Guardar Todo")
          )
        ],
      ),
    ),
  );
}

Widget _itemCompletoDialog(
  BuildContext context, 
  String titulo, 
  String? fecha, 
  File? foto, 
  {required Function(String) onFecha, required Function(File) onFoto}
) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(titulo, style: const TextStyle(fontSize: 12)),
    subtitle: Text(
      fecha ?? "Sin fecha", 
      style: TextStyle(
        color: fecha == null ? Colors.grey : Colors.blue, 
        fontWeight: FontWeight.bold, 
        fontSize: 11
      )
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón Calendario
        IconButton(
          icon: const Icon(Icons.calendar_month, size: 20),
          onPressed: () async {
            DateTime? p = await showDatePicker(
              context: context, 
              initialDate: DateTime.now(), 
              firstDate: DateTime(2020), 
              lastDate: DateTime(2035)
            );
            if (!context.mounted) return;
            if (p != null) {
              onFecha("${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}");
            }
          },
        ),
        
        // Botón Cámara / Selección de Imagen
        IconButton(
          icon: Icon(
            foto == null ? Icons.camera_alt_outlined : Icons.check_circle, 
            color: foto == null ? Colors.grey : Colors.green, 
            size: 20
          ),
          onPressed: () async {
            // 1. Mostramos menú para elegir origen (Cámara o Carpeta)
            final ImageSource? origen = await showDialog<ImageSource>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Seleccionar imagen", style: TextStyle(fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text("Cámara (Webcam)"),
                      onTap: () => Navigator.pop(ctx, ImageSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder),
                      title: const Text("Carpeta (Archivos)"),
                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            );

            // Si el usuario cancela el menú, salimos
            if (origen == null) return;

            // 2. Ejecutamos el selector según la opción elegida
            final picker = ImagePicker();
            final picked = await picker.pickImage(
              source: origen, 
              imageQuality: 50
            );
            
            if (!context.mounted) return;
            
            if (picked != null) {
              onFoto(File(picked.path));
            }
          },
        ),
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
  
  // --- FUNCIÓN PARA EDITAR CAMPOS DE TEXTO ---
  Future<void> _editarCampoTexto(String campo, String etiqueta, String valorActual) async {
    final ctrl = TextEditingController(text: valorActual == "Sin datos" || valorActual == "---" ? "" : valorActual);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Editar $etiqueta"),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: "Ingrese $etiqueta"),
          textCapitalization: TextCapitalization.characters,
          keyboardType: (campo == 'TELEFONO' || campo == 'CUIL' || campo == 'DNI') 
              ? TextInputType.number : TextInputType.text,
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

  // --- FUNCIÓN PARA SELECCIONAR EMPRESA ---
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

  // --- FUNCIÓN PARA ASIGNAR EQUIPOS (TRACTOR / ACOPLADO) ---
  void _seleccionarEquipo(String tipoFirestore, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Asignar $label"),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> empleadoSnapshot) {
              if (!empleadoSnapshot.hasData) return const Center(child: CircularProgressIndicator());

              List<String> dominiosOcupados = [];
              for (var doc in empleadoSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['TRACTOR'] != null && data['TRACTOR'] != "") dominiosOcupados.add(data['TRACTOR']);
                if (data['BATEA_TOLVA'] != null && data['BATEA_TOLVA'] != "") dominiosOcupados.add(data['BATEA_TOLVA']);
              }

              return StreamBuilder(
                stream: tipoFirestore == 'TRACTOR'
                    ? FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', isEqualTo: 'TRACTOR').snapshots()
                    : FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', whereIn: ['BATEA', 'TOLVA']).snapshots(),
                builder: (context, AsyncSnapshot<QuerySnapshot> vehiculoSnapshot) {
                  if (!vehiculoSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final unidadesLibres = vehiculoSnapshot.data!.docs.where((doc) {
                    final dominio = doc['DOMINIO'];
                    return !dominiosOcupados.contains(dominio);
                  }).toList();

                  return ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.not_interested, color: Colors.red),
                        title: Text("QUITAR $label", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        onTap: () async {
                          final nav = Navigator.of(dialogContext);
                          await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({tipoFirestore: ""});
                          if (!dialogContext.mounted) return;
                          nav.pop();
                        },
                      ),
                      const Divider(),
                      ...unidadesLibres.map((doc) => ListTile(
                        leading: const Icon(Icons.local_shipping, color: Colors.green),
                        title: Text(doc['DOMINIO']),
                        subtitle: Text(doc['TIPO']),
                        onTap: () async {
                          final nav = Navigator.of(dialogContext);
                          await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({tipoFirestore: doc['DOMINIO']});
                          if (!dialogContext.mounted) return;
                          nav.pop();
                        },
                      )),
                    ],
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("CERRAR"))],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ficha del Personal"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        actions: [
          // BOTÓN ELIMINAR CHOFER
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            onPressed: () async {
              bool? confirmar = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("¿Eliminar Personal?"),
                  content: const Text("Esta acción borrará al chofer permanentemente."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text("ELIMINAR", style: TextStyle(color: Colors.white))
                    ),
                  ],
                ),
              );

              if (confirmar == true) {
                await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).delete();
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chofer eliminado")));
              }
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
        builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          final u = snapshot.data!.data() as Map<String, dynamic>;
          
          return SingleChildScrollView(
            child: Column(children: [
              // CABECERA AZUL
              Container(
                width: double.infinity, 
                color: Colors.blue.shade900, 
                padding: const EdgeInsets.all(24), 
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => _editarCampoTexto('CHOFER', 'Nombre Completo', u['CHOFER']),
                    child: Row(
                      children: [
                        Expanded(child: Text(u['CHOFER']?.toUpperCase() ?? "S/D", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                        const Icon(Icons.edit, color: Colors.white70, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(children: [
                    _botonAsignar("TRACTOR", u['TRACTOR'], () => _seleccionarEquipo('TRACTOR', 'Tractor')),
                    const SizedBox(width: 10),
                    _botonAsignar("ACOPLADO", u['BATEA_TOLVA'], () => _seleccionarEquipo('BATEA_TOLVA', 'Acoplado')),
                  ]),
                ])
              ),
              
              tituloSeccion("DATOS PERSONALES"),
              filaDato(Icons.badge, "DNI", formatearDNI(u['DNI'])),
              InkWell(onTap: () => _editarCampoTexto('CUIL', 'CUIL', u['CUIL'] ?? ""), child: filaDato(Icons.fingerprint, "CUIL", formatearCUIL(u['CUIL'] ?? "---"))),
              InkWell(onTap: () => _editarCampoTexto('TELEFONO', 'TELÉFONO', u['TELEFONO'] ?? ""), child: filaDato(Icons.phone, "TELÉFONO", u['TELEFONO'] ?? "Sin datos")),
              InkWell(onTap: () => _seleccionarEmpresa('EMPLEADOS', widget.dni), child: filaDato(Icons.business, "EMPRESA", u['EMPRESA'] ?? "Sin datos")),
              
              tituloSeccion("VENCIMIENTOS (TOCAR PARA EDITAR)"),
              filaVtoSemaforo(context, "(EPAP) PREOCUPACIONAL", u['EPAP'], idSujeto: widget.dni, campoFirestore: 'EPAP', coleccionDestino: 'EMPLEADOS', urlFoto: u['FOTO_EPAP']),  
              filaVtoSemaforo(context, "(LICENCIA DE CONDUCIR)", u['LIC_COND'], idSujeto: widget.dni, campoFirestore: 'LIC_COND', coleccionDestino: 'EMPLEADOS', urlFoto: u['FOTO_LIC_COND']),
              filaVtoSemaforo(context, "CURSO MANEJO DEFENSIVO", u['CURSO_MANEJO'], idSujeto: widget.dni, campoFirestore: 'CURSO_MANEJO', coleccionDestino: 'EMPLEADOS', urlFoto: u['FOTO_CURSO_MANEJO']),
              filaVtoSemaforo(context, "CURSO MERCANCÍAS PELIGROSAS", u['CURSO_MERCANCIAS'], idSujeto: widget.dni, campoFirestore: 'CURSO_MERCANCIAS', coleccionDestino: 'EMPLEADOS', urlFoto: u['FOTO_CURSO_MERCANCIAS']),
            ]),
          );
        },
      ),
    );
  }

  Widget _botonAsignar(String label, String? valor, VoidCallback tap) {
    return Expanded(
      child: InkWell(
        onTap: tap, 
        child: Container(
          padding: const EdgeInsets.all(10), 
          decoration: BoxDecoration(color: Colors.white.withAlpha(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white30)), 
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            Text(valor == null || valor == "" ? "ASIGNAR" : valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ])
        )
      )
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

  void _dialogNuevoEquipo() {
    final dCtrl = TextEditingController(); // Dominio/Patente
    final mCtrl = TextEditingController(); // Marca
    final modCtrl = TextEditingController(); // Modelo
    final vCtrl = TextEditingController(); // VIN
    String tipoSel = 'TRACTOR';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setSt) => AlertDialog(
        title: const Text("Nuevo Equipo"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              value: tipoSel, 
              isExpanded: true, 
              items: ['TRACTOR', 'BATEA', 'TOLVA'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), 
              onChanged: (v) => setSt(() => tipoSel = v!)
            ),
            TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "Dominio (Patente)"), textCapitalization: TextCapitalization.characters),
            TextField(controller: mCtrl, decoration: const InputDecoration(labelText: "Marca"), textCapitalization: TextCapitalization.characters),
            TextField(controller: modCtrl, decoration: const InputDecoration(labelText: "Modelo"), textCapitalization: TextCapitalization.characters),
            // Solo mostramos VIN si es Tractor
            if (tipoSel == 'TRACTOR')
              TextField(controller: vCtrl, decoration: const InputDecoration(labelText: "Nro de VIN (Chasis)"), textCapitalization: TextCapitalization.characters),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () async {
            if (dCtrl.text.isEmpty) return;
            final nav = Navigator.of(ctx);
            await FirebaseFirestore.instance.collection('VEHICULOS').doc(dCtrl.text.toUpperCase().trim()).set({
              'DOMINIO': dCtrl.text.toUpperCase().trim(), 
              'TIPO': tipoSel,
              'MARCA': mCtrl.text.toUpperCase(),
              'MODELO': modCtrl.text.toUpperCase(),
              'VIN': tipoSel == 'TRACTOR' ? vCtrl.text.toUpperCase() : 'N/A', // VIN condicional
              'ESTADO': 'ACTIVO'
            });
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
            Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: InputDecoration(hintText: "Buscar dominio...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), onChanged: (v) => setState(() => _searchQuery = v.toUpperCase()))),
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
  
  // --- FUNCIÓN PARA EDITAR TEXTOS (MARCA, MODELO, AÑO) ---
  Future<void> _editarCampoTexto(String campo, String etiqueta, String valorActual) async {
    final ctrl = TextEditingController(text: valorActual == "S/D" || valorActual == "---" ? "" : valorActual);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Editar $etiqueta"),
        content: TextField(
          controller: ctrl, 
          textCapitalization: TextCapitalization.characters,
          keyboardType: campo == 'AÑO' ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(hintText: "Ingrese $etiqueta"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('VEHICULOS').doc(widget.carData['DOMINIO']).update({
                campo: ctrl.text.trim().toUpperCase()
              });
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            }, 
            child: const Text("Guardar")
          )
        ],
      ),
    );
  }

  // --- FUNCIÓN PARA SELECCIONAR EMPRESA DESDE LISTA ---
  void _seleccionarEmpresaVehiculo(String dominio) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Seleccionar Empresa Propietaria"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresasDisponibles.map((emp) => ListTile(
            title: Text(emp),
            onTap: () async {
              await FirebaseFirestore.instance.collection('VEHICULOS').doc(dominio).update({'EMPRESA': emp});
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
          )).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Ficha: ${widget.carData['DOMINIO']}"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        actions: [
          // BOTÓN ELIMINAR VEHÍCULO
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            tooltip: "Eliminar vehículo",
            onPressed: () async {
              bool? confirmar = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("¿Eliminar Equipo?"),
                  content: Text("¿Seguro que quieres borrar el dominio ${widget.carData['DOMINIO']} de la base de datos?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text("ELIMINAR", style: TextStyle(color: Colors.white))
                    ),
                  ],
                ),
              );

              if (confirmar == true) {
                await FirebaseFirestore.instance.collection('VEHICULOS').doc(widget.carData['DOMINIO']).delete();
                if (!context.mounted) return;
                Navigator.pop(context); // Vuelve a la lista de administración
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vehículo eliminado correctamente")));
              }
            },
          ),
        ],
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
                
                tituloSeccion("FICHA TÉCNICA (TOCAR PARA EDITAR)"),
                
                InkWell(
                  onTap: () => _editarCampoTexto('MARCA', 'MARCA', v['MARCA'] ?? "S/D"), 
                  child: filaDato(Icons.branding_watermark, "MARCA", v['MARCA'] ?? "S/D")
                ),
                
                InkWell(
                  onTap: () => _editarCampoTexto('MODELO', 'MODELO', v['MODELO'] ?? "S/D"), 
                  child: filaDato(Icons.directions_car, "MODELO", v['MODELO'] ?? "S/D")
                ),
                
                InkWell(
                  onTap: () => _editarCampoTexto('AÑO', 'AÑO', v['AÑO'] ?? "S/D"), 
                  child: filaDato(Icons.calendar_today, "AÑO", v['AÑO'] ?? "S/D")
                ),
                
                InkWell(
                  onTap: () => _seleccionarEmpresaVehiculo(v['DOMINIO']), 
                  child: filaDato(Icons.business, "EMPRESA", v['EMPRESA'] ?? "S/D")
                ),
                
                tituloSeccion("DOCUMENTACIÓN (TOCAR PARA EDITAR)"),
                
                filaVtoSemaforo(
                  context, "VENCIMIENTO RTO", v['VENCIMIENTO_RTO'], 
                  idSujeto: v['DOMINIO'], 
                  campoFirestore: 'VENCIMIENTO_RTO', 
                  coleccionDestino: 'VEHICULOS', 
                  urlFoto: v['FOTO_VENCIMIENTO_RTO']
                ),
                
                filaVtoSemaforo(
                  context, "VENCIMIENTO PÓLIZA", v['VENCIMIENTO_POLIZA'], 
                  idSujeto: v['DOMINIO'], 
                  campoFirestore: 'VENCIMIENTO_POLIZA', 
                  coleccionDestino: 'VEHICULOS', 
                  urlFoto: v['FOTO_VENCIMIENTO_POLIZA']
                ),
                
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MisDocumentosScreen extends StatelessWidget {
  final String dni;
  const MisDocumentosScreen({super.key, required this.dni});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Documentos"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).snapshots(),
        builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data!.data() as Map<String, dynamic>;
          final String nombre = user['CHOFER'] ?? "Usuario";
          final String tractorAsignado = user['TRACTOR'] ?? "";
          final String acopladoAsignado = user['BATEA_TOLVA'] ?? "";

          return SingleChildScrollView(
            child: Column(
              children: [
                cabeceraFicha(nombre, "DNI: ${formatearDNI(user['DNI'])}"),
                
                tituloSeccion("MI DOCUMENTACIÓN PERSONAL"),
                filaVtoSemaforo(context, "LICENCIA DE CONDUCIR", user['LIC_COND'], 
                    idSujeto: dni, campoFirestore: 'LIC_COND',
                    onSubir: () => _subirSolicitudImagen(context, idSujeto: dni, nombreSujeto: nombre, documentoEtiqueta: "LICENCIA", campoFirestore: "LIC_COND", coleccionDestino: 'EMPLEADOS'), 
                    urlFoto: user['FOTO_LIC_COND']),
                filaVtoSemaforo(context, "PREOCUPACIONAL (EPAP)", user['EPAP'], 
                    idSujeto: dni, campoFirestore: 'EPAP',
                    onSubir: () => _subirSolicitudImagen(context, idSujeto: dni, nombreSujeto: nombre, documentoEtiqueta: "EPAP", campoFirestore: "EPAP", coleccionDestino: 'EMPLEADOS'), 
                    urlFoto: user['FOTO_EPAP']),
                filaVtoSemaforo(context, "CURSO MANEJO DEFENSIVO", user['CURSO_MANEJO'], 
                    idSujeto: dni, campoFirestore: 'CURSO_MANEJO',
                    onSubir: () => _subirSolicitudImagen(context, idSujeto: dni, nombreSujeto: nombre, documentoEtiqueta: "CURSO MANEJO", campoFirestore: "CURSO_MANEJO", coleccionDestino: 'EMPLEADOS'), 
                    urlFoto: user['FOTO_CURSO_MANEJO']),
                filaVtoSemaforo(context, "CURSO MERCANCÍAS PELIGROSAS", user['CURSO_MERCANCIAS'], 
                    idSujeto: dni, campoFirestore: 'CURSO_MERCANCIAS',
                    onSubir: () => _subirSolicitudImagen(context, idSujeto: dni, nombreSujeto: nombre, documentoEtiqueta: "MERCANCIAS", campoFirestore: "CURSO_MERCANCIAS", coleccionDestino: 'EMPLEADOS'), 
                    urlFoto: user['FOTO_CURSO_MERCANCIAS']),

                if (tractorAsignado.isNotEmpty || acopladoAsignado.isNotEmpty) ...[
                  tituloSeccion("DOCUMENTACIÓN DE MI EQUIPO"),
                  if (tractorAsignado.isNotEmpty)
                    _StreamDocumentacionVehiculo(dominio: tractorAsignado, etiqueta: "TRACTOR"),
                  if (acopladoAsignado.isNotEmpty)
                    _StreamDocumentacionVehiculo(dominio: acopladoAsignado, etiqueta: "ACOPLADO / BATEA"),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StreamDocumentacionVehiculo extends StatelessWidget {
  final String dominio;
  final String etiqueta;
  const _StreamDocumentacionVehiculo({required this.dominio, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(dominio).snapshots(),
      builder: (context, AsyncSnapshot<DocumentSnapshot> vehiculoSnapshot) {
        if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) {
          return filaDato(Icons.warning, etiqueta, "$dominio (No cargado)");
        }

        final v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              width: double.infinity,
              color: Colors.blue.withAlpha(25),
              child: Text("$etiqueta: $dominio", 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
            ),
            filaVtoSemaforo(context, "VENCIMIENTO RTO", v['VENCIMIENTO_RTO'], 
                idSujeto: dominio, campoFirestore: 'VENCIMIENTO_RTO',
                onSubir: () => _subirSolicitudImagen(context, idSujeto: dominio, nombreSujeto: "EQUIPO $dominio", documentoEtiqueta: "RTO", campoFirestore: "VENCIMIENTO_RTO", coleccionDestino: 'VEHICULOS'), 
                urlFoto: v['FOTO_VENCIMIENTO_RTO']),
            filaVtoSemaforo(context, "VENCIMIENTO PÓLIZA", v['VENCIMIENTO_POLIZA'], 
                idSujeto: dominio, campoFirestore: 'VENCIMIENTO_POLIZA',
                onSubir: () => _subirSolicitudImagen(context, idSujeto: dominio, nombreSujeto: "EQUIPO $dominio", documentoEtiqueta: "POLIZA", campoFirestore: "VENCIMIENTO_POLIZA", coleccionDestino: 'VEHICULOS'), 
                urlFoto: v['FOTO_VENCIMIENTO_POLIZA']),
            const Divider(),
          ],
        );
      },
    );
  }
}

// --- COMPONENTES VISUALES ---

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

Widget filaVtoSemaforo(BuildContext context, String titulo, String? fecha, {
  required String idSujeto, 
  required String campoFirestore, 
  VoidCallback? onSubir, 
  String? urlFoto, 
  String? coleccionDestino,
}) {
  return StreamBuilder(
    stream: FirebaseFirestore.instance
        .collection('SOLICITUDES')
        .where('ID_SUJETO', isEqualTo: idSujeto)
        .where('CAMPO_FIRESTORE', isEqualTo: campoFirestore)
        .where('ESTADO', isEqualTo: 'PENDIENTE')
        .snapshots(),
    builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
      bool tienePendiente = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

      // Colores del semáforo
      Color bg = Colors.grey;
      int dias = _calcularDiasRestantes(fecha);
      if (fecha != null && fecha != "---" && fecha != "nan" && fecha.isNotEmpty) {
        bg = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
      }

      bool tieneFoto = urlFoto != null && urlFoto.isNotEmpty && urlFoto != "null" && urlFoto != "---";

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), 
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)), 
                        child: Text(formatearFecha(fecha), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      ),
                      if (tienePendiente) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                          child: const Row(
                            children: [
                              Icon(Icons.history, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text("EN REVISIÓN", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ]
              )
            ),
            
            // 1. VER FOTO (Ojo azul)
            if (tieneFoto)
              IconButton(
                icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                onPressed: () {
                  showDialog(
                    context: context, 
                    builder: (_) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          AppBar(
                            title: Text(titulo), 
                            automaticallyImplyLeading: false, 
                            actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]
                          ),
                          InteractiveViewer(child: Image.network(urlFoto, fit: BoxFit.contain)),
                        ]
                      )
                    )
                  );
                },
              ),

            // 2. ACCIONES (ADMIN O CHOFER)
            if (coleccionDestino != null)
              // Menú para el Administrador
              PopupMenuButton<String>(
                icon: const Icon(Icons.settings_suggest, color: Colors.blueGrey),
                onSelected: (value) async {
                  if (value == 'fecha') {
                    _gestionarFechaAdmin(context, idSujeto, campoFirestore, coleccionDestino);
                  } else if (value == 'foto') {
                    await _subirImagenDirectaAdmin(context, idSujeto, campoFirestore, coleccionDestino);
                  } else if (value == 'eliminar_foto' && tieneFoto) {
                    await _confirmarEliminarImagen(context, coleccionDestino, idSujeto, campoFirestore, urlFoto);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'fecha', child: ListTile(leading: Icon(Icons.calendar_month), title: Text("Gestionar Fecha"))),
                  PopupMenuItem(value: 'foto', child: ListTile(leading: const Icon(Icons.camera_alt), title: Text(tieneFoto ? "Reemplazar Foto" : "Subir Foto"))),
                  if (tieneFoto)
                    const PopupMenuItem(value: 'eliminar_foto', child: ListTile(leading: Icon(Icons.delete_forever, color: Colors.red), title: Text("Eliminar Foto", style: TextStyle(color: Colors.red)))),
                ],
              )
            else if (onSubir != null)
              // Botón para el Chofer
              IconButton(
                icon: Icon(
                  tienePendiente ? Icons.hourglass_top : Icons.cloud_upload_outlined, 
                  color: tienePendiente ? Colors.orange : Colors.blue
                ), 
                onPressed: tienePendiente ? () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ya tienes una actualización en revisión.")));
                } : onSubir,
              ),
          ]
        )
      );
    }
  );
}

// --- FUNCIÓN PARA EL ADMIN ---
Future<void> _gestionarFechaAdmin(BuildContext context, String idSujeto, String campoFirestore, String coleccionDestino) async {
  final String? accion = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Gestión de Vencimiento"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'borrar'), 
          child: const Text("BORRAR FECHA", style: TextStyle(color: Colors.red))
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, 'editar'), 
          child: const Text("CAMBIAR FECHA")
        ),
      ],
    ),
  );

  if (!context.mounted || accion == null) return;

  if (accion == 'borrar') {
    await FirebaseFirestore.instance.collection(coleccionDestino).doc(idSujeto).update({campoFirestore: "---"});
  } else if (accion == 'editar') {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      String nuevaFecha = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      await FirebaseFirestore.instance.collection(coleccionDestino).doc(idSujeto).update({campoFirestore: nuevaFecha});
    }
  }
}