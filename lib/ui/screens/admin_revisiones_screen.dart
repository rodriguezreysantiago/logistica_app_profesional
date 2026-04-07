import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../../core/utils/formatters.dart';

class AdminRevisionesScreen extends StatelessWidget {
  const AdminRevisionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Se mantiene igual el StreamBuilder
    return Scaffold(
      appBar: AppBar(
        title: const Text("Revisiones Pendientes"),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('REVISIONES').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all, size: 50, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("No hay pedidos pendientes.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    data['nombre_usuario'] ?? "Usuario Desconocido",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "${data['etiqueta']} - Vence: ${AppFormatters.formatearFecha(data['fecha_vencimiento'])}",
                  ),
                  trailing: const Icon(Icons.remove_red_eye, size: 20, color: Colors.grey),
                  onTap: () => _mostrarDetalleRevision(context, doc.id, data),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- FUNCIÓN DE APROBACIÓN CORREGIDA ---
  Future<void> _procesarDecision(BuildContext context, String idSolicitud, bool aprobado, Map<String, dynamic> data) async {
    // Mostrar un loader mientras procesa
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      if (aprobado) {
        String coleccion = data['coleccion_destino'] ?? 'EMPLEADOS';
        String idDestino = data['dni']; // El DNI del chofer o Patente del vehículo
        String campoFecha = data['campo']; // Ej: "LIC_COND"
        String nuevaFecha = data['fecha_vencimiento'];
        String urlArchivo = data['url_archivo'];

        // IMPORTANTE: Creamos el nombre del campo de la foto automáticamente
        // Si el campo es LIC_COND, guardamos la URL en FOTO_LIC_COND
        String campoFoto = "FOTO_$campoFecha";

        // Actualizamos el documento destino (Crea el campo de la foto si no existe)
        await FirebaseFirestore.instance.collection(coleccion).doc(idDestino).update({
          campoFecha: nuevaFecha,
          campoFoto: urlArchivo,
        });
      }

      // Borramos la solicitud de la lista de pendientes
      await FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud).delete();

      if (context.mounted) {
        Navigator.pop(context); // Quita el loader
        Navigator.pop(context); // Cierra el modal de detalle
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(aprobado ? "Solicitud Aprobada y datos actualizados" : "Solicitud Rechazada"),
            backgroundColor: aprobado ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _mostrarDetalleRevision(BuildContext context, String idDoc, Map<String, dynamic> data) {
    final String url = data['url_archivo'] ?? "";
    final bool esPdf = url.toLowerCase().contains('.pdf');

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(data['etiqueta'] ?? "Revisión"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Solicitante: ${data['nombre_usuario'] ?? 'N/A'}", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 15),

            if (esPdf)
              Column(
                children: [
                  const Icon(Icons.picture_as_pdf, size: 60, color: Colors.red),
                  const Text("Documento PDF"),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final Uri uri = Uri.parse(url);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text("VER PDF COMPLETO"),
                  ),
                ],
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  height: 250,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
                ),
              ),

            const SizedBox(height: 15),
            const Text("Nueva fecha propuesta:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              AppFormatters.formatearFecha(data['fecha_vencimiento']),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => _procesarDecision(context, idDoc, false, data),
            child: const Text("RECHAZAR", style: TextStyle(color: Colors.red)),
          ),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CERRAR")),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () => _procesarDecision(context, idDoc, true, data),
                child: const Text("APROBAR"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}