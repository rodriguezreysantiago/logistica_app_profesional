import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../shared/utils/app_feedback.dart';

/// Servicio thin de mutaciones simples sobre VEHICULOS.
///
/// Espejo conceptual de `EmpleadoActions` para Flota — cada inline-edit
/// del bottom sheet de detalle delega acá. Centralizar las llamadas en
/// un único punto:
/// - Garantiza que cada update lleve `fecha_ultima_actualizacion` para
///   trackear cambios.
/// - Audit log fire-and-forget (`AuditAccion.editarVehiculo`) para
///   bitácora unificada.
/// - Manejo de errores con SnackBar consistente.
///
/// **Lo que NO hace este servicio**: la sincronización con Volvo
/// (`VolvoApiService`), los uploads a Storage (`StorageService`), ni
/// la lógica del odómetro retroactivo (TELEMETRIA_HISTORICO). Eso
/// queda en sus servicios dedicados.
class VehiculoActions {
  VehiculoActions._();

  /// Actualiza un campo simple en el doc del vehículo. `valor` puede
  /// ser `null` para limpiar el campo.
  static Future<void> dato(
    BuildContext context,
    String patente,
    String campo,
    dynamic valor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final pat = patente.trim().toUpperCase();
    if (pat.isEmpty) {
      AppFeedback.errorOn(messenger, 'Patente vacía.');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(AppCollections.vehiculos)
          .doc(pat)
          .update({
        campo: valor,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      unawaited(AuditLog.registrar(
        accion: AuditAccion.editarVehiculo,
        entidad: 'VEHICULOS',
        entidadId: pat,
        detalles: {'campo': campo, 'nuevo_valor': valor?.toString() ?? ''},
      ));
      AppFeedback.successOn(messenger, 'Actualizado: $campo');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al actualizar: $e');
    }
  }
}
