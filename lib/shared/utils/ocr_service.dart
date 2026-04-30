import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Servicio de OCR para extraer fechas de comprobantes (carnets,
/// certificados, etc.) usando ML Kit on-device.
///
/// **Plataformas soportadas:** Android e iOS. En Windows / Linux /
/// macOS desktop / Web devuelve `null` silenciosamente porque ML Kit
/// no tiene binding para esas plataformas. Los callers deben asumir
/// que el OCR es un "nice to have" y caer al ingreso manual si falla.
///
/// Uso:
/// ```dart
/// final fecha = await OcrService.detectarFecha(xfile.path);
/// if (fecha != null) {
///   fechaCtrl.text = '${fecha.day}/${fecha.month}/${fecha.year}';
/// }
/// ```
class OcrService {
  OcrService._();

  /// Devuelve `true` si la plataforma actual soporta el OCR.
  ///
  /// Útil para mostrar el botón "detectar fecha" solo cuando va a
  /// funcionar — en Web o desktop el botón se oculta.
  static bool get soportado {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Corre OCR sobre la imagen en [path] y devuelve la fecha más
  /// probable de vencimiento.
  ///
  /// Estrategia: extraemos todas las fechas que matchean los formatos
  /// comunes (DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY) y elegimos la más
  /// **lejana en el futuro** — el chofer está fotografiando la
  /// renovación, así que la fecha de vencimiento es la última visible
  /// en el carnet (no la fecha de emisión).
  ///
  /// Si no encuentra ninguna fecha válida, devuelve `null` y el caller
  /// cae al ingreso manual.
  static Future<DateTime?> detectarFecha(String path) async {
    if (!soportado) return null;

    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final result = await recognizer.processImage(inputImage);
      return _extraerFechaMasLejana(result.text);
    } catch (e) {
      debugPrint('OCR falló: $e');
      return null;
    } finally {
      await recognizer.close();
    }
  }

  /// Busca todas las fechas en [texto] y devuelve la más lejana.
  /// Soporta separadores `/`, `-` y `.`. Año en 4 dígitos.
  ///
  /// Ejemplos que matchea:
  /// - "Vence el 15/12/2027"
  /// - "Válido hasta 03-08-2026"
  /// - "Expira: 30.06.2026"
  ///
  /// No considera años en 2 dígitos para evitar falsos positivos
  /// (ej. "2/3/26" podría ser una fracción o un código de control).
  @visibleForTesting
  static DateTime? extraerFechaMasLejana(String texto) =>
      _extraerFechaMasLejana(texto);

  static DateTime? _extraerFechaMasLejana(String texto) {
    // Regex captura DD MM YYYY donde los separadores son `/`, `-` o `.`
    // y el día/mes pueden tener 1 o 2 dígitos. El año es siempre 4
    // dígitos para reducir ambigüedad (ver doc arriba).
    final regex = RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b');
    final matches = regex.allMatches(texto);
    DateTime? mejor;

    for (final m in matches) {
      final dia = int.tryParse(m.group(1)!);
      final mes = int.tryParse(m.group(2)!);
      final anio = int.tryParse(m.group(3)!);
      if (dia == null || mes == null || anio == null) continue;
      if (mes < 1 || mes > 12 || dia < 1 || dia > 31) continue;
      // Construir y validar (rechaza 31 de febrero, etc. por rollover).
      final fecha = DateTime(anio, mes, dia);
      if (fecha.day != dia || fecha.month != mes || fecha.year != anio) {
        continue;
      }
      // Filtramos años absurdamente lejanos o pasados — el comprobante
      // de un trámite siempre tiene fecha cercana al presente +/- 10 años.
      if (anio < 2020 || anio > 2050) continue;
      if (mejor == null || fecha.isAfter(mejor)) {
        mejor = fecha;
      }
    }
    return mejor;
  }
}
