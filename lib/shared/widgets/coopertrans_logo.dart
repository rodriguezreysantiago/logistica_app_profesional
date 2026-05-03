import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Tamaño del logo. Cada uno está calibrado para un contexto específico:
///
/// - [CoopertransLogoSize.xl]: splash screen, login (logo dominante).
/// - [CoopertransLogoSize.m]: cards de bienvenida, headers de sección.
/// - [CoopertransLogoSize.s]: mini-logo en AppBar (a la izquierda del título).
enum CoopertransLogoSize { xl, m, s }

/// Logo tipográfico de Coopertrans Móvil.
///
/// Diseño: "Coopertrans" en blanco bold + "Móvil" en [AppColors.brand]
/// (azul cobalto). Sin glifos ni assets externos — escalable y consistente
/// en cualquier resolución / DPI.
///
/// El widget calcula tamaños y spacing en función del enum [size]; no
/// hace falta tunear nada en el call site.
class CoopertransLogo extends StatelessWidget {
  final CoopertransLogoSize size;

  /// Si es `true`, fuerza el ancho mínimo y centra. Útil en splash/login.
  /// En AppBar (size=s) conviene `false` para que se ajuste al espacio.
  final bool centered;

  const CoopertransLogo({
    super.key,
    this.size = CoopertransLogoSize.m,
    this.centered = false,
  });

  double get _fontSize {
    switch (size) {
      case CoopertransLogoSize.xl:
        return 36;
      case CoopertransLogoSize.m:
        return 22;
      case CoopertransLogoSize.s:
        return 14;
    }
  }

  double get _letterSpacing {
    switch (size) {
      case CoopertransLogoSize.xl:
        return 2.5;
      case CoopertransLogoSize.m:
        return 1.5;
      case CoopertransLogoSize.s:
        return 0.8;
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = RichText(
      textAlign: centered ? TextAlign.center : TextAlign.start,
      text: TextSpan(
        style: TextStyle(
          fontSize: _fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: _letterSpacing,
          height: 1.0,
        ),
        children: const [
          TextSpan(
            text: 'Coopertrans',
            style: TextStyle(color: Colors.white),
          ),
          TextSpan(
            text: ' Móvil',
            style: TextStyle(color: AppColors.brand),
          ),
        ],
      ),
    );

    if (!centered) return row;
    return Center(child: row);
  }
}
