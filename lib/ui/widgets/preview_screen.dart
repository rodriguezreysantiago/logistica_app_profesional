import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 

class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    // Verificamos si es PDF
    bool esPdf = url.toLowerCase().contains('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
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
                  maxScale: 8.0, // Mantenemos el zoom alto para legibilidad
                  // Se eliminó 'enableTextSelection' para evitar error de compilación
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
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white30, size: 60),
                      SizedBox(height: 10),
                      Text("No se pudo cargar la imagen", 
                        style: TextStyle(color: Colors.white30, fontSize: 12)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}