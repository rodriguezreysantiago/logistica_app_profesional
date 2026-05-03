import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/coopertrans_logo.dart';

/// Splash inicial al abrir la app.
///
/// Es 100% cosmético: muestra el logo grande sobre un gradient oscuro
/// durante un tiempo corto, después salta a [AppRoutes.home] donde el
/// AuthGuard decide si va al MainPanel o a Login.
///
/// No bloquea la inicialización de la app — esa ya se hizo en `main()`
/// antes de runApp(). Acá solo damos un beat visual de marca antes del
/// primer frame "real".
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _duracionSplash = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    // Programamos la salida después del primer frame para no perdernos
    // el efecto si la app arranca con el frame ya pintado pero el timer
    // empezando antes de tiempo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(_duracionSplash, _salir);
    });
  }

  void _salir() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.brandDark,
              AppColors.background,
            ],
          ),
        ),
        child: const Stack(
          children: [
            Center(
              child: CoopertransLogo(
                size: CoopertransLogoSize.xl,
                centered: true,
              ),
            ),
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(AppColors.brand),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    AppTexts.tagline,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
