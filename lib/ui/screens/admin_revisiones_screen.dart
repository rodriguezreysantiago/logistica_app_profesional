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
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fact_check, size: 60, color: Colors.white.withAlpha(50)),
                        const SizedBox(height: 15),
                        const Text("No hay trámites pendientes.", style: TextStyle(color: Colors.white70, fontSize: 16)),
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
                    bool esCambioEquipo = data['tipo_solicitud'] == 'CAMBIO_EQUIPO';
                    String idAfectado = (data['dni'] ?? data['patente'] ?? "N/A").toString().toUpperCase();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: esCambioEquipo ? Colors.orangeAccent.withAlpha(40) : Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: esCambioEquipo ? Colors.orangeAccent : Colors.white.withAlpha(30)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: esCambioEquipo ? Colors.orangeAccent : (esVehiculo ? Colors.blueAccent : Colors.greenAccent),
                          child: Icon(
                            esCambioEquipo ? Icons.swap_horiz : (esVehiculo ? Icons.local_shipping : Icons.person), 
                            color: Colors.white, size: 20
                          ),
                        ),
                        title: Text(
                          "${data['nombre_usuario'] ?? 'Usuario'} -> $idAfectado",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                        subtitle: Text(
                          esCambioEquipo 
                            ? "SOLICITA: ${data['patente']}\n(Sueltas: ${data['unidad_actual'] ?? '-'})"
                            : "${data['etiqueta'] ?? 'Documento'}\nVence: ${AppFormatters.formatearFecha(data['fecha_vencimiento'])}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
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
    bool esCambioEquipo = data['tipo_solicitud'] == 'CAMBIO_EQUIPO';
    final String url = data['url_archivo'] ?? "";
    final String etiqueta = data['etiqueta'] ?? "Documento";
    final String idAfectado = (data['dni'] ?? data['patente'] ?? "N/A").toString().toUpperCase();

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
                Text("Solicitante: ${data['nombre_usuario'] ?? 'N/A'}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Divider(color: Colors.white12, height: 30),
                
                if (esCambioEquipo) ...[
                  const Icon(Icons.swap_vert_circle, size: 80, color: Colors.orangeAccent),
                  const SizedBox(height: 15),
                  _buildFilaDialogo("SUELTA:", data['unidad_actual'] ?? "NINGUNA", Colors.redAccent),
                  const SizedBox(height: 10),
                  _buildFilaDialogo("SOLICITA:", data['patente'] ?? "S/D", Colors.greenAccent),
                ] else ...[
                  GestureDetector(
                    onTap: () {
                      if (url.isNotEmpty) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (context) => PreviewScreen(url: url, titulo: "$etiqueta - $idAfectado"),
                        ));
                      }
                    },
                    child: url.toLowerCase().contains('.pdf')
                        ? const Column(
                            children: [
                              Icon(Icons.picture_as_pdf, size: 70, color: Colors.redAccent),
                              Text("VER PDF", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                            ],
                          )
                        // ✅ Mentora: Manejo profesional de imágenes de red.
                        : Image.network(
                            url, 
                            height: 200, 
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox(
                                height: 200,
                                child: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => const SizedBox(
                              height: 150,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image, color: Colors.white24, size: 50),
                                  Text("Error al cargar imagen", style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Text("NUEVO VENCIMIENTO PROPUESTO:", style: TextStyle(color: Colors.white54, fontSize: 10)),
                  Text(AppFormatters.formatearFecha(data['fecha_vencimiento']),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                ],
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
    // ✅ Mentora: Guardamos referencias ANTES de la operación asíncrona.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Cerramos el diálogo inmediatamente para dar feedback de rapidez al usuario
    navigator.pop();
    
    final bool esCambioEquipo = data['tipo_solicitud'] == 'CAMBIO_EQUIPO';

    try {
      if (aprobado) {
        if (esCambioEquipo) {
          final batch = FirebaseFirestore.instance.batch();
          final String dni = data['dni'];
          final String nueva = data['patente'];
          final String actual = data['unidad_actual'];
          final bool esTractor = data['campo'] == 'SOLICITUD_VEHICULO';

          // 1. Actualizar Empleado
          batch.update(FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni), {
            esTractor ? 'VEHICULO' : 'ENGANCHE': nueva,
            'ultima_actualizacion': FieldValue.serverTimestamp(),
          });

          // 2. Liberar unidad vieja
          if (actual.isNotEmpty && actual != "-" && actual != "SIN ASIGNAR") {
            batch.update(FirebaseFirestore.instance.collection('VEHICULOS').doc(actual), {'ESTADO': 'LIBRE'});
          }

          // 3. Ocupar unidad nueva
          batch.update(FirebaseFirestore.instance.collection('VEHICULOS').doc(nueva), {'ESTADO': 'OCUPADO'});

          // 4. Borrar solicitud
          batch.delete(FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud));

          await batch.commit();
        } else {
          // Lógica para papeles
          final String coleccion = data['coleccion_destino'] ?? 'EMPLEADOS';
          final String idDestino = (data['dni'] ?? data['patente'] ?? "").toString().trim().toUpperCase();
          final String campoVencimiento = data['campo'] ?? ''; 
          final String urlArchivo = data['url_archivo'] ?? '';

          if (idDestino.isNotEmpty && campoVencimiento.isNotEmpty) {
            String campoArchivo = campoVencimiento.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
            await FirebaseFirestore.instance.collection(coleccion).doc(idDestino).update({
              campoVencimiento: data['fecha_vencimiento'],
              campoArchivo: urlArchivo,
              "ultima_actualizacion_sistema": FieldValue.serverTimestamp(),
            });
          }
          await FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud).delete();
        }
      } else {
        // Rechazado: Solo borramos la solicitud
        await FirebaseFirestore.instance.collection('REVISIONES').doc(idSolicitud).delete();
      }

      // ✅ Mentora: Usamos la referencia guardada, 100% seguro contra crasheos.
      messenger.showSnackBar(
        SnackBar(
          content: Text(aprobado ? "Operación exitosa" : "Solicitud descartada"),
          backgroundColor: aprobado ? Colors.green : Colors.redAccent,
        ),
      );
    } catch (e) {
      debugPrint("Error en proceso: $e");
      messenger.showSnackBar(
        SnackBar(content: Text("Ocurrió un error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildFilaDialogo(String label, String valor, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}