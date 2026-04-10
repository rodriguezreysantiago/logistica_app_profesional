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
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.5)),
          
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('REVISIONES').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.done_all, size: 60, color: Colors.white.withValues(alpha: 0.5)),
                        const SizedBox(height: 15),
                        const Text("No hay pedidos pendientes.", 
                          style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Colors.orangeAccent.withValues(alpha: 0.8),
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          data['nombre_usuario'] ?? "Usuario Desconocido",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          "${data['etiqueta'] ?? 'S/D'}\nVence: ${AppFormatters.formatearFecha(data['fecha_vencimiento'])}",
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        trailing: const Icon(Icons.remove_red_eye_outlined, color: Colors.white70),
                        onTap: () => _mostrarDetalleRevision(context, doc.id, data),
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
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(etiqueta, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Solicitante: ${data['nombre_usuario'] ?? 'N/A'}", 
                   style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(height: 15),
              
              GestureDetector(
                onTap: () {
                  if (url.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PreviewScreen(url: url, titulo: etiqueta),
                      ),
                    );
                  }
                },
                child: esPdf
                  ? const Column(
                      children: [
                        Icon(Icons.picture_as_pdf, size: 80, color: Colors.redAccent),
                        SizedBox(height: 8),
                        Text("VER PDF COMPLETO", 
                          style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(url, height: 200, fit: BoxFit.cover),
                    ),
              ),
              const SizedBox(height: 15),
              Text(AppFormatters.formatearFecha(data['fecha_vencimiento']),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _procesarDecision(dialogContext, idDoc, false, data),
            child: const Text("RECHAZAR", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => _procesarDecision(dialogContext, idDoc, true, data),
            child: const Text("APROBAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _procesarDecision(BuildContext context, String idSolicitud, bool aprobado, Map<String, dynamic> data) async {
    // 1. GUARDAMOS LAS REFERENCIAS ANTES DE CUALQUIER AWAIT
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // 2. MOSTRAR LOADING
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
    );
    
    try {
      if (aprobado) {
        final String coleccion = data['coleccion_destino'] ?? 'EMPLEADOS';
        final String idDestino = data['dni']?.toString() ?? ''; 
        final String campoFecha = data['campo'] ?? '';
        final String nuevaFecha = data['fecha_vencimiento'] ?? '';
        final String urlArchivo = data['url_archivo'] ?? '';

        if (idDestino.isEmpty || campoFecha.isEmpty) throw "Datos incompletos.";

        String nombreCampoArchivo = campoFecha.toUpperCase().startsWith('VENCIMIENTO_') 
            ? campoFecha.toUpperCase().replaceFirst('VENCIMIENTO_', 'ARCHIVO_')
            : "ARCHIVO_${campoFecha.toUpperCase()}";

        await FirebaseFirestore.instance.collection(coleccion).doc(idDestino).set({
          campoFecha: nuevaFecha,
          nombreCampoArchivo: urlArchivo,
          "ultima_revision": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud).delete();

      // 3. NAVEGACIÓN SEGURA USANDO LA REFERENCIA GUARDADA
      // Cerramos Loading y Detalle
      navigator.pop(); // Cierra Loading
      navigator.pop(); // Cierra Detalle

      // 4. MOSTRAR ÉXITO (Solo si el widget sigue vivo)
      if (!context.mounted) return;

      final Color color = aprobado ? Colors.greenAccent : Colors.redAccent;

      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: Text(aprobado ? "¡OPERACIÓN EXITOSA!" : "SOLICITUD RECHAZADA", 
               style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          content: const Text("Se han actualizado los registros correctamente.", style: TextStyle(color: Colors.white70)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black),
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("ENTENDIDO"),
            )
          ],
        ),
      );

    } catch (e) {
      // Si falla, cerramos el loading usando la referencia
      if (navigator.canPop()) navigator.pop(); 
      messenger.showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }
}