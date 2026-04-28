import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Visor full-screen de archivos remotos.
///
/// Detecta automáticamente el tipo de archivo:
/// - **PDF** (`.pdf`): usa `PdfViewer.uri` de pdfrx con navegación de páginas
/// - **Imagen**: usa `Image.network` con `InteractiveViewer` para hacer zoom
///
/// Las URLs vienen típicamente de Firebase Storage. Se ignoran query params
/// (como `?alt=media&token=...`) al detectar la extensión.
class PreviewScreen extends StatelessWidget {
  final String url;
  final String titulo;

  const PreviewScreen({
    super.key,
    required this.url,
    required this.titulo,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(),
        body: _buildErrorPlaceholder('URL de documento no válida'),
      );
    }

    final urlSinParametros = url.split('?').first.toLowerCase();
    final esPdf = urlSinParametros.endsWith('.pdf');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      backgroundColor: Colors.black,
      body: esPdf ? _buildPdfViewer() : _buildImageViewer(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        titulo.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.black.withAlpha(150),
      elevation: 0,
      foregroundColor: Colors.white,
    );
  }

  // ===========================================================================
  // VISOR DE PDF
  //
  // Usamos los defaults de pdfrx para loading y error. Antes había builders
  // custom forzados con `as dynamic`, pero esa API cambió de versión y los
  // builders quedaban ignorados (bug silenciado). Ahora pdfrx maneja loading
  // y errores con su UI propia (funciona, aunque menos personalizada).
  // ===========================================================================
  Widget _buildPdfViewer() {
    return PdfViewer.uri(
      Uri.parse(url),
      params: const PdfViewerParams(
        maxScale: 8.0,
        backgroundColor: Colors.black,
      ),
    );
  }

  // ===========================================================================
  // VISOR DE IMÁGENES con zoom interactivo
  // ===========================================================================
  Widget _buildImageViewer(BuildContext context) {
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
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              _buildErrorPlaceholder('La imagen no está disponible'),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String mensaje) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white24,
            size: 50,
          ),
          const SizedBox(height: 15),
          Text(
            mensaje,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
