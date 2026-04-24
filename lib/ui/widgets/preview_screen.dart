import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 

class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    // ✅ Mentora: Detección a prueba de balas. 
    // Ignoramos los tokens de Firebase cortando desde el '?' y verificamos la extensión real.
    final urlSinParametros = url.split('?').first.toLowerCase();
    final bool esPdf = urlSinParametros.endsWith('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black, 
      body: Center(
        child: esPdf
            ? PdfViewer.uri(
                Uri.parse(url),
                params: const PdfViewerParams(
                  maxScale: 8.0, // Zoom potente para ver letras chicas de pólizas
                  backgroundColor: Colors.black,
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
                        color: Colors.orangeAccent,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white24, size: 50),
                      SizedBox(height: 10),
                      Text("Error al cargar el documento", 
                        style: TextStyle(color: Colors.white24, fontSize: 13)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}