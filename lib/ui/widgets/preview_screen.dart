import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 

class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    bool esPdf = url.toLowerCase().contains('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: esPdf
            ? PdfViewer.uri(
                Uri.parse(url),
                // Eliminamos los builders que están dando problemas de versión
                params: const PdfViewerParams(
                  maxScale: 8.0,
                ),
              )
            : InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(color: Colors.white);
                  },
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    color: Colors.white30,
                    size: 50,
                  ),
                ),
              ),
      ),
    );
  }
}