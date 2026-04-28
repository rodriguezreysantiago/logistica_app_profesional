import '../../../shared/utils/formatters.dart';
import '../widgets/vencimiento_item.dart';

/// Genera el texto del mensaje de WhatsApp para avisarle a un chofer
/// sobre un vencimiento.
///
/// El tono y el nivel de urgencia cambia según los días restantes:
/// - >= 30 días: aviso preventivo, formal.
/// - 15-29: recordatorio, "empezá el trámite".
/// - 1-14: alerta, urgente.
/// - Vencido: vencido en X días, hay que regularizar YA.
class AvisoVencimientoBuilder {
  AvisoVencimientoBuilder._();

  /// Arma el mensaje listo para mandar por WhatsApp.
  ///
  /// [item]: el vencimiento (chofer o vehículo).
  /// [destinatarioNombre]: primer nombre del chofer al que se le manda
  ///   (ej. "Juan"). Si es null, se usa "hola" genérico.
  ///
  /// Cada mensaje termina con una nota que aclara que el aviso fue
  /// generado automáticamente desde el sistema, para que el chofer
  /// sepa que no es un mensaje individual del admin y para encuadrar
  /// el tono.
  static String build({
    required VencimientoItem item,
    String? destinatarioNombre,
  }) {
    final saludo = destinatarioNombre != null && destinatarioNombre.isNotEmpty
        ? 'Hola $destinatarioNombre'
        : 'Hola';

    final fechaFmt = AppFormatters.formatearFecha(item.fecha);
    final esVehiculo = item.coleccion == 'VEHICULOS';
    final referencia = esVehiculo
        // Para tractor/batea, el "titulo" ya viene como "TRACTOR - AB123CD".
        ? 'la unidad ${_extraerPatente(item.titulo) ?? item.docId}'
        // Para chofer, mencionamos el documento personalizado.
        : 'tu ${item.tipoDoc.toLowerCase()}';

    final cuerpo = _cuerpo(item, saludo, esVehiculo, referencia, fechaFmt);
    return '$cuerpo\n\n$_firmaAutomatica';
  }

  /// Texto principal del aviso (sin firma). Separado para que el
  /// switch por días quede legible.
  static String _cuerpo(
    VencimientoItem item,
    String saludo,
    bool esVehiculo,
    String referencia,
    String fechaFmt,
  ) {
    if (item.dias < 0) {
      // ▼ VENCIDO
      final hace = -item.dias;
      final tiempoTexto = hace == 1 ? 'ayer' : 'hace $hace días';
      return '$saludo. Te aviso desde la oficina: '
          '${esVehiculo ? "el ${item.tipoDoc} de $referencia" : referencia} '
          'venció $tiempoTexto (era el $fechaFmt). '
          'Es urgente regularizarlo. ¿Cuándo podés acercarte a presentar el comprobante?';
    }

    if (item.dias == 0) {
      return '$saludo. Te aviso que '
          '${esVehiculo ? "el ${item.tipoDoc} de $referencia" : referencia} '
          'vence HOY ($fechaFmt). Por favor pasá lo antes posible por la oficina.';
    }

    if (item.dias <= 7) {
      // ▼ MENOS DE UNA SEMANA
      return '$saludo. Recordatorio importante: '
          '${esVehiculo ? "el ${item.tipoDoc} de $referencia" : referencia} '
          'vence en ${item.dias} día${item.dias == 1 ? "" : "s"} '
          '(el $fechaFmt). Si todavía no empezaste el trámite, hacelo ya.';
    }

    if (item.dias <= 15) {
      // ▼ 8-15 DÍAS
      return '$saludo. Te aviso que '
          '${esVehiculo ? "el ${item.tipoDoc} de $referencia" : referencia} '
          'vence en ${item.dias} días ($fechaFmt). Es buen momento '
          'para empezar el trámite de renovación.';
    }

    // ▼ 16-30+ DÍAS — preventivo
    return '$saludo. Aviso preventivo: '
        '${esVehiculo ? "el ${item.tipoDoc} de $referencia" : referencia} '
        'vence el $fechaFmt (en ${item.dias} días). Andá viendo el trámite.';
  }

  /// Firma fija que se suma al final de cada aviso. El doble salto de
  /// línea + cursiva en la app de WhatsApp (con guiones bajos) lo
  /// despega del cuerpo y le baja el peso visual.
  static const String _firmaAutomatica =
      '_Mensaje automático del sistema de gestión S.M.A.R.T. Logística._\n'
      '_Para responder o gestionar el trámite, comunicate con la oficina._';

  /// Extrae la patente de títulos como "TRACTOR - AB123CD" o
  /// "BATEA - XYZ987". Si no encuentra el patrón, devuelve null.
  static String? _extraerPatente(String titulo) {
    final m = RegExp(r'-\s*([A-Z0-9]{6,})').firstMatch(titulo);
    return m?.group(1);
  }
}
