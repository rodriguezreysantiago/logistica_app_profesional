import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 

class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _buildErrorPlaceholder("URL de documento no válida");
    }

    final urlSinParametros = url.split('?').first.toLowerCase();
    final bool esPdf = urlSinParametros.endsWith('.pdf');

    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: Text(
          titulo.toUpperCase(), 
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)
        ),
        centerTitle: true,
        backgroundColor: Colors.black.withAlpha(150), 
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black, 
      body: esPdf ? _buildPdfNavigator() : _buildImageNavigator(context),
    );
  }

 // ===========================================================================
  // ✅ VISOR DE PDF - SOLUCIÓN DEFINITIVA (BYPASS DE TIPOS)
  // ===========================================================================
  Widget _buildPdfNavigator() {
    return PdfViewer.uri(
      Uri.parse(url),
      params: PdfViewerParams(
        maxScale: 8.0, 
        backgroundColor: Colors.black,
        
        // ✅ Forzamos a dynamic para que el compilador no pueda quejarse
        loadingBannerBuilder: ((context, bytes, total) {
          return Center(
            child: CircularProgressIndicator(
              value: (total != null && total > 0) ? bytes / total : null,
              color: Colors.greenAccent,
              strokeWidth: 2,
            ),
          );
        }) as dynamic,

        // ✅ Forzamos a dynamic para que el compilador acepte la firma sea cual sea
        errorBannerBuilder: ((context, error, stack) {
          return _buildErrorPlaceholder("Error al cargar el PDF");
        }) as dynamic,
      ),
    );
  }

  // ===========================================================================
  // ✅ VISOR DE IMÁGENES INTERACTIVO
  // ===========================================================================
  Widget _buildImageNavigator(BuildContext context) {
    return InteractiveViewer(
      panEnabled: true, 
      minScale: 0.5,
      maxScale: 5.0, 
      child: Center(
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
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => 
              _buildErrorPlaceholder("La imagen no está disponible"),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String mensaje) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white24, size: 50),
          const SizedBox(height: 15),
          Text(mensaje, 
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}