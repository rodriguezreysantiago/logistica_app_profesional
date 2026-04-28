import 'package:flutter/material.dart';

/// Tarjeta unificada para items de listas, secciones de detalle, etc.
///
/// Tiene padding y radio estandarizados para que toda la app
/// "se sienta igual". Si `onTap` es null, no es clickeable.
///
/// Uso:
/// ```
/// AppCard(
///   onTap: () => abrirDetalle(),
///   highlighted: hayPendiente,
///   child: Row(...),
/// );
/// ```
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderRadius;
  final bool highlighted;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.onTap,
    this.borderColor,
    this.borderRadius = 16,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final defaultBorder = highlighted
        ? Theme.of(context).colorScheme.primary.withAlpha(150)
        : Colors.white.withAlpha(15);

    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? defaultBorder,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(borderRadius),
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );

    return card;
  }
}
