import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coopertrans_movil/shared/utils/responsive_grid.dart';

/// Tests de widget del **patrón responsive** que comparten los 3 hubs
/// (Gomería / Logística / main_panel del chofer): LayoutBuilder +
/// `computeGridRatio()` + GridView.count con `NeverScrollableScrollPhysics`.
///
/// **Por qué no testeamos los screens reales**: cada hub tiene
/// dependencias de Firebase (StreamBuilder de banner alertas en
/// Gomería, StreamCount de contadores en Logística, AuthService
/// en main_panel). Mockearlas requiere `fake_cloud_firestore` que
/// no está en deps — overhead alto vs valor.
///
/// **Por qué SÍ vale testear el patrón**: si el patrón se rompe (ej.
/// alguien agrega un Scrollable wrapper que da alto unbounded, o
/// cambia ratio fijo, o saca el LayoutBuilder), los hubs vuelven a
/// scrollear. Estos tests de smoke pumpean el patrón con MediaQuery
/// real y verifican: (a) las cards renderean, (b) no hay overflow,
/// (c) el grid NO scrollea.
///
/// Cobertura del cálculo del ratio en sí: ver
/// `responsive_grid_test.dart` (15 unit tests puros).
void main() {
  /// Reproduce el shape exacto que usa cada hub: Padding + Column +
  /// Expanded(LayoutBuilder + GridView.count). [tilesCount] mockea
  /// las 2-5 cards del hub real.
  Widget hubLikeWidget({
    required int cols,
    required int tilesCount,
    double spacing = 16,
    double clampMin = 0.5,
  }) {
    final filas = (tilesCount / cols).ceil();
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final ratio = computeGridRatio(
                      boxWidth: constraints.maxWidth,
                      boxHeight: constraints.maxHeight,
                      cols: cols,
                      rows: filas,
                      spacing: spacing,
                      clampMin: clampMin,
                    );
                    return GridView.count(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: ratio,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(tilesCount, (i) {
                        return Container(
                          key: ValueKey('tile_$i'),
                          color: Colors.blue.shade100,
                          child: Center(child: Text('Tile $i')),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('Hub responsive — Gomería 4 tiles 2×2', () {
    testWidgets('iPhone SE portrait (375×667) renderea 4 tiles sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      // Las 4 tiles deben estar presentes.
      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 1'), findsOneWidget);
      expect(find.text('Tile 2'), findsOneWidget);
      expect(find.text('Tile 3'), findsOneWidget);
      // Verificación crítica: NO hay overflow renderizado.
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad landscape (1024×768) renderea 4 tiles sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Windows desktop (1920×1080) renderea 4 tiles sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Hub responsive — Logística 5 tiles', () {
    testWidgets('mobile portrait (375×667) → 2 cols × 3 filas, sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 5));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop (1920×1080) → 5 cols × 1 fila, sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 5, tilesCount: 5));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Hub responsive — main_panel chofer', () {
    testWidgets('chofer (3 botones) en mobile portrait sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 3));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 1'), findsOneWidget);
      expect(find.text('Tile 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admin (4 botones) en mobile portrait sin overflow',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      expect(find.text('Tile 0'), findsOneWidget);
      expect(find.text('Tile 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Hub responsive — el GridView NO scrollea', () {
    testWidgets('NeverScrollableScrollPhysics está activo (no se puede scrollear)',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      final gridView = tester.widget<GridView>(find.byType(GridView));
      expect(gridView.physics, isA<NeverScrollableScrollPhysics>());
    });
  });

  group('Hub responsive — pantalla extrema', () {
    testWidgets('pantalla microscópica (100×100) NO crashea',
        (tester) async {
      tester.view.physicalSize = const Size(100, 100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Pantalla absurdamente chica: con padding 16+16 + spacing,
      // las celdas quedan muy chicas. Validación: NO crashea, las
      // tiles existen aunque sean diminutas.
      await tester.pumpWidget(hubLikeWidget(cols: 2, tilesCount: 4));

      // No nos importa si los textos son visibles a esa escala —
      // solo que NO haya exception del LayoutBuilder por NaN o
      // ratio negativo (que el helper computeGridRatio defiende
      // con clamp y fallback).
      expect(tester.takeException(), isNull);
    });
  });
}
