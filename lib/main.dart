import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'firebase_options.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';


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

// --- GESTIÓN DE IMÁGENES CORREGIDA ---

// 1. FUNCIÓN PARA INICIAR EL PROCESO (FECHA + ARCHIVO)
  Future<void> _subirSolicitudImagen(BuildContext context, {
    required String idSujeto,
    required String nombreSujeto,
    required String documentoEtiqueta,
    required String campoFirestore,
    required String coleccionDestino,
  }) async {
    
    // PASO A: SELECCIONAR FECHA
    DateTime? fechaElegida = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: "PASO 1: SELECCIONAR VENCIMIENTO",
      locale: const Locale('es', 'AR'),
    );

    if (fechaElegida == null || !context.mounted) return;
    
    String fechaFormateada = "${fechaElegida.year}-${fechaElegida.month.toString().padLeft(2, '0')}-${fechaElegida.day.toString().padLeft(2, '0')}";

    // PASO B: SELECCIONAR ARCHIVO
    File? archivoSeleccionado;
    
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text("PASO 2: ADJUNTAR A $documentoEtiqueta", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Vencimiento: $fechaFormateada"),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Cámara (Sacar foto)'),
              onTap: () async {
                final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
                if (img != null) {
                  archivoSeleccionado = File(img.path);
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.green),
              title: const Text('Galería o Archivo'),
              onTap: () async {
                final res = await FilePicker.platform.pickFiles(type: FileType.any);
                if (res != null && res.files.single.path != null) {
                  archivoSeleccionado = File(res.files.single.path!);
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    );

    // PASO C: 
    if (archivoSeleccionado != null && context.mounted) {
      _procederALaSubidaFinal(
        context, 
        idSujeto, 
        documentoEtiqueta, 
        campoFirestore, 
        archivoSeleccionado!, 
        fechaFormateada,
        "PERSONAL" // <-- Aquí le decimos que la colección destino es PERSONAL, pero podrías hacer lógica para decidirlo según el campo o etiqueta
      );
    }
  }

// 2. FUNCIÓN DE SUBIDA FINAL (CORREGIDA Y UNIFICADA)
  void _procederALaSubidaFinal(BuildContext context, String dni, String etiqueta, String campo, File archivo, String fechaS, String coleccionDestino) async {
  
  // 1. Mostrar el cartel de carga
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Row(
          children: const [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text("Subiendo archivo...")),
          ],
        ),
      );
    },
  );

  try {
    // 2. Determinar el tipo de archivo (MIME Type) para que no llegue sin formato
    String extension = archivo.path.split('.').last.toLowerCase();
    String contentType = 'application/octet-stream'; // Por defecto
    if (extension == 'pdf') contentType = 'application/pdf';
    if (extension == 'jpg' || extension == 'jpeg') contentType = 'image/jpeg';
    if (extension == 'png') contentType = 'image/png';

    // 3. Subida a Firebase Storage con METADATOS
    final String nombreArchivo = '${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = FirebaseStorage.instance.ref().child('REVISIONES/$nombreArchivo');
    
    // Agregamos SettableMetadata para que Firebase sepa qué archivo es
    await ref.putFile(archivo, SettableMetadata(contentType: contentType));
    
    String url = await ref.getDownloadURL();

    // 4. Guardar registro en Firestore (Colección REVISIONES en MAYÚSCULAS)
    await FirebaseFirestore.instance.collection('REVISIONES').add({
      'DNI': dni.trim(),
      'CAMPO': campo, 
      'CAMPO_FOTO': 'FOTO_$campo', 
      'COLECCION_DESTINO': coleccionDestino, 
      'ETIQUETA': etiqueta,
      'NUEVA_FECHA': fechaS,
      'URL_ADJUNTO': url,
      'ESTADO': 'PENDIENTE',
      'FECHA_SOLICITUD': DateTime.now(),
    });

    // 5. Éxito: Cerramos el diálogo y avisamos
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Cierra el Alert de carga
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$etiqueta: Enviado a revisión con éxito"), 
          backgroundColor: Colors.green
        ),
      );
    }

  } catch (e) {
    // 6. Error: Cerramos el diálogo y mostramos el error
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Cierra el Alert de carga
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al subir: $e"), 
          backgroundColor: Colors.red
        ),
      );
    }
    debugPrint("Error en la subida: $e");
  }
}

Future<void> _subirImagenDirectaAdmin(BuildContext context, String idSujeto, String campoFirestore, String coleccionDestino) async {
  final ImagePicker picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);

  if (image == null || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Actualizando imagen...")])
    ),
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
      Navigator.pop(context); // Cierra loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imagen actualizada con éxito")));
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // Cierra loading
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
  const _SeccionSolicitudesPendientesAdmin();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Control de Vencimientos"), backgroundColor: Colors.blueGrey),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('REVISIONES')
            .where('ESTADO', isEqualTo: 'PENDIENTE')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No hay trámites pendientes"));

          final solicitudes = snapshot.data!.docs;
          return ListView.builder(
            itemCount: solicitudes.length,
            itemBuilder: (context, index) {
              // ✅ Cambiamos 'sol' por 'doc' para que coincida con la lógica de abajo
              final doc = solicitudes[index];
              final data = doc.data() as Map<String, dynamic>;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.assignment, color: Colors.blueGrey),
                  title: Text(data['ETIQUETA'] ?? 'Sin Título'),
                  subtitle: Text("ID: ${data['DNI']} - Vto: ${data['NUEVA_FECHA']}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _mostrarDetalleSolicitud(context, doc), // ✅ Pasamos 'doc'
                ),
              );
            },
          );
        },
      ),
    );
  }
}



// --- FUNCIÓN ÚNICA Y FINAL PARA MOSTRAR DETALLE Y GESTIONAR ---
void _mostrarDetalleSolicitud(BuildContext context, DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Revisar: ${data['ETIQUETA'] ?? 'Trámite'}"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("ID / Patente: ${data['DNI']}", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Nueva Fecha: ${data['NUEVA_FECHA']}"),
            const SizedBox(height: 15),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.remove_red_eye),
                label: const Text("VER ARCHIVO ADJUNTO"),
                onPressed: () => _verFotoGrande(context, data['URL_ADJUNTO'], data['ETIQUETA'] ?? "Documento"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await doc.reference.update({'ESTADO': 'RECHAZADO'});
            if (context.mounted) Navigator.pop(ctx);
          },
          child: const Text("RECHAZAR", style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () async {
            // 1. Declaramos la variable FUERA del try para que el SnackBar la vea
            String coleccionFinal = "EMPLEADOS"; 

            try {
              String idDocumento = data['DNI'].toString().trim();
              String campoAActualizar = data['CAMPO'] ?? '';
              String nuevaUrl = data['URL_ADJUNTO'] ?? '';
              String nuevaFecha = data['NUEVA_FECHA'] ?? '';
              
              String destinoTramite = (data['COLECCION_DESTINO'] ?? '').toString().toUpperCase();

              // 2. Lógica de selección de carpeta
              if (destinoTramite.contains("VEHICULOS") || destinoTramite.contains("UNIDADES")) {
                coleccionFinal = "VEHICULOS";
              } else {
                bool esPatente = RegExp(r'^[A-Z0-9]{6,7}$').hasMatch(idDocumento);
                if (esPatente) coleccionFinal = "VEHICULOS";
              }

              // 3. Actualización
              await FirebaseFirestore.instance
                  .collection(coleccionFinal)
                  .doc(idDocumento)
                  .update({
                campoAActualizar: nuevaFecha,
                'FOTO_$campoAActualizar': nuevaUrl,
                'FOTO': nuevaUrl, 
              });

              await doc.reference.update({'ESTADO': 'APROBADO'});

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("¡$coleccionFinal actualizado correctamente!"), 
                    backgroundColor: Colors.green
                  ),
                );
              }
            } catch (e) {
              debugPrint("Error al aprobar: $e");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error: No se encontró el registro en $coleccionFinal."), 
                    backgroundColor: Colors.red
                  ),
                );
              }
            }
          },
          child: const Text("APROBAR Y ACTUALIZAR", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}


  Future<void> rechazarSolicitud(BuildContext context, DocumentSnapshot sol) async {
    await sol.reference.update({'ESTADO': 'RECHAZADO'});
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

void _dialogNuevoChofer(BuildContext context) {
  final nomCtrl = TextEditingController();
  final dniCtrl = TextEditingController();
  final cuilCtrl = TextEditingController();
  final telCtrl = TextEditingController();
  final passCtrl = TextEditingController(); // Controlador para la clave

  String empresaSeleccionada = empresasDisponibles.first;
  bool obscurePass = true; // Para mostrar/ocultar clave

  // Vencimientos
  String vtoLicencia = "---";
  String vtoLinti = "---";
  String vtoEpap = "---";
  String vtoManejo = "---";

  // Archivos
  File? fileLicencia; String nameLicencia = "Sin archivo";
  File? fileLinti; String nameLinti = "Sin archivo";
  File? fileEpap; String nameEpap = "Sin archivo";
  File? fileManejo; String nameManejo = "Sin archivo";

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSt) => AlertDialog(
        title: const Text("Nuevo Personal"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: "NOMBRE COMPLETO"), textCapitalization: TextCapitalization.characters),
                TextField(controller: dniCtrl, decoration: const InputDecoration(labelText: "DNI"), keyboardType: TextInputType.number),
                
                // CAMPO DE CONTRASEÑA NUEVO
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: "CONTRASEÑA DE ACCESO",
                    suffixIcon: IconButton(
                      icon: Icon(obscurePass ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
                
                TextField(controller: cuilCtrl, decoration: const InputDecoration(labelText: "CUIL"), keyboardType: TextInputType.number),
                TextField(controller: telCtrl, decoration: const InputDecoration(labelText: "TELÉFONO"), keyboardType: TextInputType.phone),
                
                DropdownButtonFormField<String>(
                  initialValue: empresaSeleccionada,
                  decoration: const InputDecoration(labelText: "EMPRESA"),
                  items: empresasDisponibles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setSt(() => empresaSeleccionada = v!),
                ),
                const Divider(),

                // 1. LICENCIA
                _buildSelectorArchivo(
                  titulo: "VTO. LICENCIA DE CONDUCIR",
                  fecha: vtoLicencia,
                  nombreArchivo: nameLicencia,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => vtoLicencia = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) setSt(() { fileLicencia = File(result.files.single.path!); nameLicencia = result.files.single.name; });
                  }
                ),

                // 2. LINTI
                _buildSelectorArchivo(
                  titulo: "VTO. CURSO LINTI",
                  fecha: vtoLinti,
                  nombreArchivo: nameLinti,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => vtoLinti = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) setSt(() { fileLinti = File(result.files.single.path!); nameLinti = result.files.single.name; });
                  }
                ),

                const SizedBox(height: 10),

                // 3. EPAP
                _buildSelectorArchivo(
                  titulo: "VTO. EPAP (PREOCUPACIONAL)",
                  fecha: vtoEpap,
                  nombreArchivo: nameEpap,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => vtoEpap = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) setSt(() { fileEpap = File(result.files.single.path!); nameEpap = result.files.single.name; });
                  }
                ),

                const SizedBox(height: 10),

                // 4. MANEJO DEFENSIVO
                _buildSelectorArchivo(
                  titulo: "VTO. MANEJO DEFENSIVO",
                  fecha: vtoManejo,
                  nombreArchivo: nameManejo,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => vtoManejo = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) setSt(() { fileManejo = File(result.files.single.path!); nameManejo = result.files.single.name; });
                  }
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () async {
              if (nomCtrl.text.isEmpty || dniCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nombre, DNI y Clave son obligatorios")));
                return;
              }
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
              
              try {
                String urlLic = "---"; String urlLinti = "---";
                String urlEpap = "---"; String urlManejo = "---";

                if (fileLicencia != null) {
                  final ref = FirebaseStorage.instance.ref().child('EMPLEADOS/${dniCtrl.text}/LICENCIA_$nameLicencia');
                  await ref.putFile(fileLicencia!); urlLic = await ref.getDownloadURL();
                }
                if (fileLinti != null) {
                  final ref = FirebaseStorage.instance.ref().child('EMPLEADOS/${dniCtrl.text}/LINTI_$nameLinti');
                  await ref.putFile(fileLinti!); urlLinti = await ref.getDownloadURL();
                }
                if (fileEpap != null) {
                  final ref = FirebaseStorage.instance.ref().child('EMPLEADOS/${dniCtrl.text}/EPAP_$nameEpap');
                  await ref.putFile(fileEpap!); urlEpap = await ref.getDownloadURL();
                }
                if (fileManejo != null) {
                  final ref = FirebaseStorage.instance.ref().child('EMPLEADOS/${dniCtrl.text}/MANEJO_$nameManejo');
                  await ref.putFile(fileManejo!); urlManejo = await ref.getDownloadURL();
                }

                await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniCtrl.text.trim()).set({
                  'CHOFER': nomCtrl.text.toUpperCase().trim(),
                  'DNI': dniCtrl.text.trim(),
                  'CLAVE': passCtrl.text.trim(), // Se guarda la clave aquí
                  'CUIL': cuilCtrl.text.trim(),
                  'TELEFONO': telCtrl.text.trim(),
                  'EMPRESA': empresaSeleccionada,
                  'LIC_COND': vtoLicencia,
                  'FOTO_LIC_COND': urlLic,
                  'CURSO_MERCANCIAS': vtoLinti,
                  'FOTO_CURSO_MERCANCIAS': urlLinti,
                  'EPAP': vtoEpap,
                  'FOTO_EPAP': urlEpap,
                  'CURSO_MANEJO': vtoManejo,
                  'FOTO_CURSO_MANEJO': urlManejo,
                  'TRACTOR': '',
                  'BATEA_TOLVA': '',
                });

                if (!context.mounted) return;
                Navigator.pop(context); // Cierra loading
                Navigator.pop(ctx);     // Cierra diálogo
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("GUARDAR PERSONAL"),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Personal")),
      floatingActionButton: FloatingActionButton(onPressed: () => _dialogNuevoChofer(context), 
  child: const Icon(Icons.add, color: Colors.white),
),
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

  // Importante: Asegurate de tener este import arriba de todo en el archivo:
// import 'package:file_picker/file_picker.dart';

void _dialogNuevoVehiculo(BuildContext context) {
  final domCtrl = TextEditingController();
  final marcaCtrl = TextEditingController();
  final modeloCtrl = TextEditingController();
  final anioCtrl = TextEditingController();
  
  String tipoSeleccionado = 'TRACTOR';
  String empresaSeleccionada = empresasDisponibles.first;
  String fechaRTO = "---";
  String fechaSeguro = "---";
  
  // Ahora guardamos la ruta del archivo y el nombre para mostrarlo
  File? fileRTO;
  String nameRTO = "Sin archivo";
  File? fileSeguro;
  String nameSeguro = "Sin archivo";

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSt) => AlertDialog(
        title: const Text("Nuevo Vehículo / Equipo"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: domCtrl, decoration: const InputDecoration(labelText: "DOMINIO (PATENTE)"), textCapitalization: TextCapitalization.characters),
                DropdownButtonFormField<String>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(labelText: "TIPO DE UNIDAD"),
                  items: ['TRACTOR', 'BATEA', 'TOLVA'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setSt(() => tipoSeleccionado = v!),
                ),
                TextField(controller: marcaCtrl, decoration: const InputDecoration(labelText: "MARCA"), textCapitalization: TextCapitalization.characters),
                TextField(controller: modeloCtrl, decoration: const InputDecoration(labelText: "MODELO"), textCapitalization: TextCapitalization.characters),
                TextField(controller: anioCtrl, decoration: const InputDecoration(labelText: "AÑO"), keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  initialValue: empresaSeleccionada,
                  decoration: const InputDecoration(labelText: "EMPRESA PROPIETARIA"),
                  items: empresasDisponibles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setSt(() => empresaSeleccionada = v!),
                ),
                const Divider(height: 30),
                
                // SECCIÓN RTO (IMAGEN O PDF)
                _buildSelectorArchivo(
                  titulo: "VENCIMIENTO RTO",
                  fecha: fechaRTO,
                  nombreArchivo: nameRTO,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => fechaRTO = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) {
                      setSt(() {
                        fileRTO = File(result.files.single.path!);
                        nameRTO = result.files.single.name;
                      });
                    }
                  }
                ),

                const SizedBox(height: 15),

                // SECCIÓN SEGURO (IMAGEN O PDF)
                _buildSelectorArchivo(
                  titulo: "VENCIMIENTO SEGURO",
                  fecha: fechaSeguro,
                  nombreArchivo: nameSeguro,
                  onFecha: () async {
                    DateTime? p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) setSt(() => fechaSeguro = "${p.year}-${p.month.toString().padLeft(2,'0')}-${p.day.toString().padLeft(2,'0')}");
                  },
                  onFile: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                    if (result != null) {
                      setSt(() {
                        fileSeguro = File(result.files.single.path!);
                        nameSeguro = result.files.single.name;
                      });
                    }
                  }
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () async {
              if (domCtrl.text.isEmpty) return;
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
              try {
                String urlRTO = "---";
                String urlSeguro = "---";

                if (fileRTO != null) {
                  final ref = FirebaseStorage.instance.ref().child('VEHICULOS/${domCtrl.text}/RTO_$nameRTO');
                  await ref.putFile(fileRTO!);
                  urlRTO = await ref.getDownloadURL();
                }
                if (fileSeguro != null) {
                  final ref = FirebaseStorage.instance.ref().child('VEHICULOS/${domCtrl.text}/SEGURO_$nameSeguro');
                  await ref.putFile(fileSeguro!);
                  urlSeguro = await ref.getDownloadURL();
                }

                await FirebaseFirestore.instance.collection('VEHICULOS').doc(domCtrl.text.toUpperCase().trim()).set({
                  'DOMINIO': domCtrl.text.toUpperCase().trim(),
                  'TIPO': tipoSeleccionado,
                  'MARCA': marcaCtrl.text.toUpperCase().trim(),
                  'MODELO': modeloCtrl.text.toUpperCase().trim(),
                  'AÑO': anioCtrl.text.trim(),
                  'EMPRESA': empresaSeleccionada,
                  'VENCIMIENTO_RTO': fechaRTO,
                  'FOTO_VENCIMIENTO_RTO': urlRTO,
                  'VENCIMIENTO_POLIZA': fechaSeguro, 
                  'FOTO_VENCIMIENTO_POLIZA': urlSeguro,
                });

                if (!context.mounted) return;
                Navigator.pop(context); // Cierra loading
                Navigator.pop(ctx);     // Cierra diálogo
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("GUARDAR EQUIPO"),
          ),
        ],
      ),
    ),
  );
}

// Widget auxiliar para no repetir código de diseño
Widget _buildSelectorArchivo({required String titulo, required String fecha, required String nombreArchivo, required VoidCallback onFecha, required VoidCallback onFile}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
      Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Vto: $fecha", style: const TextStyle(fontSize: 13)),
              Text(nombreArchivo, style: const TextStyle(fontSize: 11, color: Colors.grey, overflow: TextOverflow.ellipsis)),
            ],
          )),
          IconButton(icon: const Icon(Icons.calendar_today, size: 20), onPressed: onFecha),
          IconButton(
            icon: Icon(Icons.attach_file, color: nombreArchivo != "Sin archivo" ? Colors.green : Colors.grey),
            onPressed: onFile,
          ),
        ],
      ),
    ],
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
       floatingActionButton: FloatingActionButton(
  backgroundColor: Colors.blue.shade900,
  // Esta es la forma correcta de pasarle el contexto:
  onPressed: () => _dialogNuevoVehiculo(context), 
  child: const Icon(Icons.add, color: Colors.white),
),
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
                filaVtoSemaforo(
  context, 
  "LICENCIA DE CONDUCIR", 
  user['LIC_COND'], 
  idSujeto: dni, 
  campoFirestore: 'LIC_COND',
  onSubir: () => _subirSolicitudImagen(
    context, 
    idSujeto: dni, 
    nombreSujeto: nombre, 
    documentoEtiqueta: "LICENCIA", 
    campoFirestore: "LIC_COND", 
    coleccionDestino: 'EMPLEADOS'
  ), 
  urlFoto: user['FOTO_LIC_COND']
),

filaVtoSemaforo(
  context, 
  "PREOCUPACIONAL (EPAP)", 
  user['EPAP'], 
  idSujeto: dni, 
  campoFirestore: 'EPAP',
  onSubir: () => _subirSolicitudImagen(
    context, 
    idSujeto: dni, 
    nombreSujeto: nombre, 
    documentoEtiqueta: "EPAP", 
    campoFirestore: "EPAP", 
    coleccionDestino: 'EMPLEADOS'
  ), 
  urlFoto: user['FOTO_EPAP']
),

filaVtoSemaforo(
  context, 
  "CURSO MANEJO DEFENSIVO", 
  user['CURSO_MANEJO'], 
  idSujeto: dni, 
  campoFirestore: 'CURSO_MANEJO',
  onSubir: () => _subirSolicitudImagen(
    context, 
    idSujeto: dni, 
    nombreSujeto: nombre, 
    documentoEtiqueta: "CURSO MANEJO", 
    campoFirestore: "CURSO_MANEJO", 
    coleccionDestino: 'EMPLEADOS'
  ), 
  urlFoto: user['FOTO_CURSO_MANEJO']
),

filaVtoSemaforo(
  context, 
  "CURSO MERCANCÍAS PELIGROSAS", 
  user['CURSO_MERCANCIAS'], 
  idSujeto: dni, 
  campoFirestore: 'CURSO_MERCANCIAS',
  onSubir: () => _subirSolicitudImagen(
    context, 
    idSujeto: dni, 
    nombreSujeto: nombre, 
    documentoEtiqueta: "MERCANCIAS", 
    campoFirestore: "CURSO_MERCANCIAS", 
    coleccionDestino: 'EMPLEADOS'
  ), 
  urlFoto: user['FOTO_CURSO_MERCANCIAS']
),
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
  String? coleccionDestino,
  String? urlFoto,
}) {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('REVISIONES')
        .where('DNI', isEqualTo: idSujeto)
        .where('CAMPO', isEqualTo: campoFirestore)
        .where('ESTADO', isEqualTo: 'PENDIENTE')
        .snapshots(),
    builder: (context, snapshot) {
      bool tienePendiente = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
      bool tieneFoto = urlFoto != null && urlFoto.isNotEmpty && urlFoto != "null" && urlFoto != "---";
      
      Color bg = Colors.grey;
      int dias = _calcularDiasRestantes(fecha);
      if (fecha != null && fecha != "---" && fecha != "nan" && fecha.isNotEmpty) {
        bg = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
      }

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
                        child: Text(
                          formatearFecha(fecha), 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                        ),
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
                ],
              ),
            ),
            if (tieneFoto)
              IconButton(
                icon: const Icon(Icons.remove_red_eye, color: Colors.blueGrey, size: 22),
                onPressed: () => _verAdjunto(context, urlFoto, titulo),
              ),
            if (coleccionDestino != null)
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
              IconButton(
                icon: Icon(
                  tienePendiente ? Icons.hourglass_top : Icons.settings, 
                  color: tienePendiente ? Colors.orange : Colors.blueGrey
                ),
                onPressed: tienePendiente 
                  ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ya tienes una actualización en revisión."))) 
                  : onSubir,
              ),
          ],
        ),
      );
    },
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

 void _verAdjunto(BuildContext context, String? url, String titulo) async {
  if (url == null || url == "---" || url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No hay un archivo o imagen cargada."))
    );
    return;
  }

  // Detectamos si es una imagen por la extensión
  bool esImagen = url.toLowerCase().contains('.jpg') || 
                  url.toLowerCase().contains('.jpeg') || 
                  url.toLowerCase().contains('.png');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: double.maxFinite,
        child: esImagen 
          ? Image.network(
              url, 
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text("Error al cargar la imagen. Intente abrir como archivo."),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file, size: 80, color: Colors.blueGrey),
                const SizedBox(height: 15),
                const Text("Este documento es un PDF o archivo externo.", textAlign: TextAlign.center),
              ],
            ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CERRAR")),
        ElevatedButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text("ABRIR / DESCARGAR"),
          onPressed: () async {
            final Uri uri = Uri.parse(url);
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No se pudo abrir el enlace."))
                );
              }
            }
          },
        ),
      ],
    ),
  );
}

// --- FUNCIÓN GLOBAL PARA SELECCIONAR ARCHIVOS ---
// Pegar esto al final del archivo main.dart (fuera de cualquier clase)
Widget _buildSelectorArchivo({
  required String titulo, 
  required String fecha, 
  required String nombreArchivo, 
  required VoidCallback onFecha, 
  required VoidCallback onFile
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
      Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Vto: $fecha", style: const TextStyle(fontSize: 13)),
              Text(nombreArchivo, 
                style: const TextStyle(fontSize: 11, color: Colors.grey, overflow: TextOverflow.ellipsis),
                maxLines: 1,
              ),
            ],
          )),
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 20), 
            onPressed: onFecha
          ),
          IconButton(
            icon: Icon(
              Icons.attach_file, 
              color: nombreArchivo != "Sin archivo" ? Colors.green : Colors.grey
            ),
            onPressed: onFile,
          ),
        ],
      ),
    ],
  );
}

// --- FUNCIÓN GLOBAL PARA VER FOTOS ---
void _verFotoGrande(BuildContext context, String? url, String titulo) async {
  if (url == null || url == "---" || url.isEmpty || url == "null") {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No hay archivo disponible."))
    );
    return;
  }

  // Detectamos si es una imagen o un archivo (PDF, etc.)
  final uri = Uri.parse(url);
  final esImagen = url.toLowerCase().contains('.jpg') || 
                   url.toLowerCase().contains('.jpeg') || 
                   url.toLowerCase().contains('.png') ||
                   url.toLowerCase().contains('image');

  if (!esImagen) {
    // PLAN B: Si no es imagen (es PDF o archivo), lo abrimos fuera de la app
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo abrir el archivo externo."))
        );
      }
    }
    return;
  }

  // PLAN A: Si es imagen, mostramos el visor que ya tenías
  if (!context.mounted) return;
  showDialog(
    context: context, 
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black, // Fondo negro para que resalte la foto
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          AppBar(
            title: Text(titulo, style: const TextStyle(color: Colors.white)), 
            automaticallyImplyLeading: false, 
            backgroundColor: Colors.blueGrey[900],
            actions: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white), 
                onPressed: () => Navigator.pop(dialogContext) 
              )
            ]
          ),
          Flexible(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url, 
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (c, e, s) => Container(
                  padding: const EdgeInsets.all(20.0),
                  color: Colors.white,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("Error al cargar imagen. Puede ser un archivo PDF."),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}