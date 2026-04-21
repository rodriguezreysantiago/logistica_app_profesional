import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';
import '../widgets/preview_screen.dart';

class AdminRevisionesScreen extends StatelessWidget {
  const AdminRevisionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Revisiones Pendientes"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A).withAlpha(220),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          Container(color: const Color(0xFF1A3A5A).withAlpha(100)),

          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('REVISIONES')
                  .orderBy('fecha_vencimiento', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fact_check,
                            size: 60, color: Colors.white.withAlpha(50)),
                        const SizedBox(height: 15),
                        const Text("No hay trámites pendientes.",
                            style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool esVehiculo = data['coleccion_destino'] == 'VEHICULOS';

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withAlpha(30)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              esVehiculo ? Colors.blueAccent : Colors.orangeAccent,
                          child: Icon(esVehiculo ? Icons.local_shipping : Icons.person,
                              color: Colors.white, size: 20),
                        ),
                        title: Text(
                          data['nombre_usuario'] ?? "Usuario Desconocido",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          "${data['etiqueta'] ?? 'Documento'}\nVence: ${AppFormatters.formatearFecha(data['fecha_vencimiento'])}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                        onTap: () {
                          // Navegación segura para Windows Desktop
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _mostrarDetalleRevision(context, doc.id, data);
                          });
                        },
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

  void _mostrarDetalleRevision(BuildContext context, String idDoc, Map<String, dynamic> data) {
    final String url = data['url_archivo'] ?? "";
    final String etiqueta = data['etiqueta'] ?? "Documento";
    final bool esPdf = url.toLowerCase().contains('.pdf');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0D1D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(etiqueta, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 5),
                Text("Solicitante: ${data['nombre_usuario'] ?? 'N/A'}",
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Divider(color: Colors.white12, height: 30),
                
                GestureDetector(
                  onTap: () {
                    if (url.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => PreviewScreen(url: url, titulo: etiqueta),
                      ));
                    }
                  },
                  child: esPdf
                      ? const Column(
                          children: [
                            Icon(Icons.picture_as_pdf, size: 70, color: Colors.redAccent),
                            SizedBox(height: 8),
                            Text("PULSAR PARA VER PDF", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)));
                            },
                            errorBuilder: (context, error, stackTrace) => 
                              const SizedBox(height: 200, child: Icon(Icons.broken_image, color: Colors.white24, size: 40)),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                const Text("NUEVO VENCIMIENTO PROPUESTO:", style: TextStyle(color: Colors.white54, fontSize: 10)),
                Text(AppFormatters.formatearFecha(data['fecha_vencimiento']),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _procesarDecision(context, idDoc, false, data),
            child: const Text("RECHAZAR", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => _procesarDecision(context, idDoc, true, data),
            child: const Text("APROBAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _procesarDecision(BuildContext context, String idSolicitud, bool aprobado, Map<String, dynamic> data) async {
    // 1. Cerramos el diálogo inmediatamente para dar respuesta visual en la PC
    Navigator.of(context).pop();

    try {
      if (aprobado) {
        final String coleccion = data['coleccion_destino'] ?? 'EMPLEADOS';
        // Limpieza de ID (DNI o Patente)
        final String idDestino = (data['dni'] ?? data['patente'] ?? "").toString().trim().toUpperCase();
        final String campoVencimiento = data['campo'] ?? ''; 
        final String nuevaFecha = data['fecha_vencimiento'] ?? '';
        final String urlArchivo = data['url_archivo'] ?? '';

        if (idDestino.isNotEmpty && campoVencimiento.isNotEmpty) {
          // LÓGICA DE PARES: VENCIMIENTO_ -> ARCHIVO_
          String campoArchivo;
          if (campoVencimiento.startsWith('VENCIMIENTO_')) {
            campoArchivo = campoVencimiento.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
          } else {
            // Caso de seguridad: Si el campo no tiene prefijo, se lo agregamos al archivo
            campoArchivo = 'ARCHIVO_$campoVencimiento';
          }

          // USAMOS UPDATE (Fire & Forget para Windows)
          FirebaseFirestore.instance.collection(coleccion).doc(idDestino).update({
            campoVencimiento: nuevaFecha,
            campoArchivo: urlArchivo,
            "fecha_ultima_actualizacion": FieldValue.serverTimestamp(),
            "ultima_revision_admin": FieldValue.serverTimestamp(),
          });
        }
      }

      // Borramos de REVISIONES
      FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud).delete();

      _mostrarFeedback(context, aprobado);

    } catch (e) {
      debugPrint("Error en proceso de aprobación: $e");
    }
  }

  void _mostrarFeedback(BuildContext context, bool aprobado) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(aprobado ? "Ficha actualizada correctamente" : "Solicitud descartada"),
        backgroundColor: aprobado ? Colors.green : Colors.redAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}