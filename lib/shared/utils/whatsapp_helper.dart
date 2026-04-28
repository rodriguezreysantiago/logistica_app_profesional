import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper para abrir conversaciones de WhatsApp con un mensaje
/// pre-armado.
///
/// Usa el esquema oficial `https://wa.me/<numero>?text=<mensaje>` (también
/// conocido como "Click-to-Chat"). Es 100% gratis, no requiere cuenta de
/// WhatsApp Business ni aprobación de Meta — abre el WhatsApp del admin
/// con el chofer cargado y el mensaje listo, y el admin solo hace click
/// en enviar.
class WhatsAppHelper {
  WhatsAppHelper._();

  /// Lanza WhatsApp con un mensaje pre-llenado.
  ///
  /// [numero] puede venir con espacios, guiones, paréntesis o el prefijo
  /// `+54 9`; se normaliza adentro. Si está vacío, abre WhatsApp sin
  /// destinatario para que el admin lo cargue manualmente.
  ///
  /// Devuelve `true` si se logró abrir, `false` si el sistema no tiene
  /// WhatsApp ni navegador disponible.
  static Future<bool> abrir({
    required String? numero,
    required String mensaje,
  }) async {
    final tel = _normalizarNumeroAr(numero ?? '');
    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      // Si el teléfono está vacío, dejamos el path en '/' y wa.me abre
      // WhatsApp sin destinatario (útil cuando el chofer no tiene tel
      // cargado y el admin va a elegir el contacto en su WhatsApp).
      path: tel.isEmpty ? '/' : '/$tel',
      queryParameters: {'text': mensaje},
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir WhatsApp: $e');
      return false;
    }
  }

  /// Normaliza un teléfono argentino al formato que requiere wa.me:
  /// solo dígitos, con código de país (54) y el "9" móvil incluido.
  ///
  /// Acepta varios formatos comunes en Argentina:
  /// - "291 5555555"        → "5492915555555"
  /// - "+54 9 291 555-5555" → "5492915555555"
  /// - "0291 15-5555555"    → "5492915555555"  (saca el 0 y el 15)
  /// - "291 15 555 5555"    → "5492915555555"
  ///
  /// Si el teléfono ya viene con +54 9 al inicio lo respeta. Si no
  /// puede normalizarlo (queda raro), devuelve el string vacío para
  /// que el admin elija destinatario manualmente en su WhatsApp.
  static String _normalizarNumeroAr(String raw) {
    if (raw.trim().isEmpty) return '';

    // 1) Solo dígitos.
    String digitos = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digitos.isEmpty) return '';

    // 2) Quitar el "0" inicial de área (formato local AR: 0291...).
    if (digitos.startsWith('0')) {
      digitos = digitos.substring(1);
    }

    // 3) Quitar el "15" después del código de área. Aparece en
    //    formatos viejos como "0291-15-5555555". Lo detectamos cuando
    //    el "15" aparece pegado al área (3-4 dígitos al inicio).
    final m15 = RegExp(r'^(\d{2,4})15(\d{6,8})$').firstMatch(digitos);
    if (m15 != null) {
      digitos = '${m15.group(1)}${m15.group(2)}';
    }

    // 4) Asegurar prefijo 54 (Argentina) y 9 (móvil).
    if (digitos.startsWith('549')) {
      // Ya está completo: 54 9 + número. OK.
    } else if (digitos.startsWith('54')) {
      // Falta el 9 entre 54 y el área.
      digitos = '549${digitos.substring(2)}';
    } else {
      // Asumimos que es número local: anteponer 54 9.
      digitos = '549$digitos';
    }

    // Sanity check de largo razonable: 549 + 10 dígitos = 13. Aceptamos
    // 12-14 para tolerar líneas con área de 2 ó 4 dígitos.
    if (digitos.length < 12 || digitos.length > 14) return '';

    return digitos;
  }
}
