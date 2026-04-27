import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/preview_screen.dart';

// ✅ MENTOR: Transformado a StatefulWidget para proteger el Stream de lecturas duplicadas
class AdminRevisionesScreen extends StatefulWidget {
  const AdminRevisionesScreen({super.key});

  @override
  State<AdminRevisionesScreen> createState() => _AdminRevisionesScreenState();
}

class _AdminRevisionesScreenState extends State<AdminRevisionesScreen> {
  late final Stream<QuerySnapshot> _revisionesStream;

  @override
  void initState() {
    super.initState();
    // ✅ MENTOR: La conexión se inicializa UNA sola vez.
    _revisionesStream = FirebaseFirestore.instance
        .collection('REVISIONES')
        .orderBy('fecha_vencimiento', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Revisiones Pendientes"),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Theme.of(context).scaffoldBackgroundColor),
            ),
          ),
          Container(color: Colors.black.withAlpha(200)),

          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: _revisionesStream, // Usamos el stream anclado en memoria
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fact_check, size: 70, color: Colors.greenAccent.withAlpha(50)),
                        const SizedBox(height: 15),
                        const Text("No hay trámites pendientes.", style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    
                    bool esVehiculo = data['coleccion_destino'] == 'VEHICULOS';
                    bool esCambioEquipo = data['tipo_solicitud'] == 'CAMBIO_EQUIPO';
                    String idAfectado = (data['dni'] ?? data['patente'] ?? "N/A").toString().toUpperCase();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: esCambioEquipo ? Colors.orangeAccent.withAlpha(20) : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: esCambioEquipo ? Colors.orangeAccent.withAlpha(100) : Colors.white.withAlpha(15)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _mostrarDetalleRevision(context, doc.id, data),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: esCambioEquipo ? Colors.orangeAccent.withAlpha(40) : (esVehiculo ? Colors.blueAccent.withAlpha(40) : Colors.greenAccent.withAlpha(40)),
                                child: Icon(
                                  esCambioEquipo ? Icons.swap_horiz : (esVehiculo ? Icons.local_shipping : Icons.person), 
                                  color: esCambioEquipo ? Colors.orangeAccent : (esVehiculo ? Colors.blueAccent : Colors.greenAccent), 
                                  size: 22
                                ),
                              ),
                              title: Text(
                                "${data['nombre_usuario'] ?? 'Usuario'} -> $idAfectado",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  esCambioEquipo 
                                    ? "SOLICITA: ${data['patente']}\n(Sueltas: ${data['unidad_actual'] ?? '-'})"
                                    : "${data['etiqueta'] ?? 'Documento'}\nVence: ${AppFormatters.formatearFecha(data['fecha_vencimiento'])}",
                                  style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                            ),
                          ),
                        ),
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
        backgroundColor: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Diseño centralizado
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(20))
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(etiqueta.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 5),
                Text("Solicitante: ${data['nombre_usuario'] ?? 'N/A'}", style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const Divider(color: Colors.white10, height: 30),
                
                if (esCambioEquipo) ...[
                  const Icon(Icons.swap_vert_circle, size: 70, color: Colors.orangeAccent),
                  const SizedBox(height: 25),
                  _buildFilaDialogo("SUELTA:", data['unidad_actual'] ?? "NINGUNA", Colors.redAccent),
                  const SizedBox(height: 12),
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
                        ? Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15)),
                            child: const Column(
                              children: [
                                Icon(Icons.picture_as_pdf, size: 60, color: Colors.redAccent),
                                SizedBox(height: 10),
                                Text("TOCAR PARA VER PDF", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              url, 
                              height: 200, 
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  height: 200,
                                  child: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) => Container(
                                height: 150,
                                color: Colors.black12,
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.white24, size: 50),
                                    SizedBox(height: 10),
                                    Text("Error al cargar imagen", style: TextStyle(color: Colors.white54)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 25),
                  const Text("NUEVO VENCIMIENTO PROPUESTO:", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(AppFormatters.formatearFecha(data['fecha_vencimiento']),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14)
                  ),
                  onPressed: () => _procesarDecision(context, idDoc, false, data),
                  child: const Text("RECHAZAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, 
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)
                  ),
                  onPressed: () => _procesarDecision(context, idDoc, true, data),
                  child: const Text("APROBAR", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _procesarDecision(BuildContext context, String idSolicitud, bool aprobado, Map<String, dynamic> data) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    navigator.pop(); // Feedback inmediato
    
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

      messenger.showSnackBar(
        SnackBar(
          content: Text(aprobado ? "Operación aprobada y guardada" : "Solicitud rechazada y eliminada", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: aprobado ? Colors.green : Colors.redAccent,
        ),
      );
    } catch (e) {
      debugPrint("Error en proceso: $e");
      messenger.showSnackBar(
        SnackBar(content: Text("Ocurrió un error en la base de datos: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildFilaDialogo(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}