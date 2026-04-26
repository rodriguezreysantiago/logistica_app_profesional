import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 

class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    // ✅ MENTOR: Excelente barrera de seguridad contra los tokens largos de Firebase.
    final urlSinParametros = url.split('?').first.toLowerCase();
    final bool esPdf = urlSinParametros.endsWith('.pdf');

    return Scaffold(
      extendBodyBehindAppBar: true, // ✅ MENTOR: Look inmersivo de pantalla completa
      appBar: AppBar(
        title: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.black.withAlpha(150), // Cristal oscuro para no tapar el documento
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black, // Fondo puro, ideal para lectura
      body: Center(
        child: esPdf
            ? SafeArea(
                child: PdfViewer.uri(
                  Uri.parse(url),
                  params: const PdfViewerParams(
                    maxScale: 8.0, 
                    backgroundColor: Colors.black,
                  ),
                ),
              )
            : InteractiveViewer(
                panEnabled: true, 
                minScale: 0.5,
                maxScale: 5.0, 
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                            : null,
                        color: Theme.of(context).colorScheme.primary, // Alineado al color principal de tu app
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white24, size: 50),
                      SizedBox(height: 15),
                      Text("El documento no está disponible", 
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}