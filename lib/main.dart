import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart';
import 'core/services/notification_service.dart';

import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

// Pantalla inicial
import 'ui/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🔥 Firebase conectado correctamente");
  } catch (e) {
    debugPrint("🚨 Error crítico al iniciar Firebase: $e");
  }

  await PrefsService.init();
  await NotificationService.init();

  runApp(const LogisticaApp());
}

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppTexts.appName,
      debugShowCheckedModeBanner: false,

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('es', 'AR'),
      ],

      locale: const Locale('es', 'AR'),

      theme: AppTheme.darkTheme,

      initialRoute: PrefsService.isLoggedIn
          ? AppRoutes.home
          : AppRoutes.login,

      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
      },

      onGenerateRoute: AppRouter.generateRoute,
      onUnknownRoute: AppRouter.unknownRoute,
    );
  }
}