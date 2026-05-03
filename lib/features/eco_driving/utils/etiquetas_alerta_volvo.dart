/// Mapa canónico de tipos del Volvo Vehicle Alerts API a etiquetas
/// legibles en español rioplatense.
///
/// Si Volvo agrega un tipo nuevo (`alertType` del payload v1.1.6+),
/// sumarlo acá. La función [etiquetaAlertaVolvo] cae al código crudo
/// como fallback — ningún caller debería romper, solo va a mostrar
/// el código en vez de una etiqueta humana hasta que sumemos el mapeo.
///
/// Mantenido sincronizado entre Cloud Functions
/// (`functions/src/index.ts::ETIQUETAS_TIPO_ALERTA`) y el cliente
/// Flutter — pero la fuente de verdad de los textos es ESTE archivo.
const Map<String, String> _etiquetasTipoAlertaVolvo = {
  'DISTANCE_ALERT': 'Cerca del vehículo de adelante',
  'IDLING': 'Motor en ralentí',
  'OVERSPEED': 'Exceso de velocidad',
  'PTO': 'Toma de fuerza activada',
  'HARSH': 'Aceleración / frenada brusca',
  'GENERIC': 'Evento genérico',
  'TELL_TALE': 'Luz de tablero encendida',
  'FUEL': 'Cambio anormal de combustible',
  'CATALYST': 'Cambio de nivel AdBlue',
  'ALARM': 'Alarma anti-robo',
  'GEOFENCE': 'Entrada/salida de geocerca',
  'SAFETY_ZONE': 'Zona de velocidad reducida',
  'TPM': 'Presión de neumático',
  'TTM': 'Temperatura de neumático',
  'AEBS': 'Frenado automático de emergencia',
  'ESP': 'Control de estabilidad',
  'DAS': 'Alerta de cansancio',
  'LKS': 'Asistente de carril',
  'LCS': 'Asistente de cambio de carril',
  'UNSAFE_LANE_CHANGE': 'Cambio de carril inseguro',
  'TACHO_OUT_OF_SCOPE_MODE_CHANGE': 'Tacógrafo fuera de servicio',
  'CARGO': 'Cambio en carga (puerta / temp)',
  'ADBLUELEVEL_LOW': 'AdBlue bajo',
  'WITHOUT_ADBLUE': 'Sin AdBlue',
  'DRIVING_WITHOUT_BEING_LOGGED_IN': 'Conducción sin chofer identificado',
  'BATTERY_PACK_HIGH_DISCHARGE': 'Descarga alta de batería',
  'BATTERY_PACK_CHARGING_STATUS_CHANGE': 'Cambio en estado de carga',
};

/// Devuelve la etiqueta legible para un `alertType` del Volvo Alerts API.
/// Si el tipo no está mapeado, devuelve el código crudo (no rompe).
String etiquetaAlertaVolvo(String tipo) =>
    _etiquetasTipoAlertaVolvo[tipo] ?? tipo;
