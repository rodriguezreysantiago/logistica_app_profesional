import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/auto_sync_service.dart';

import 'routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

// 🔹 DEPENDENCIAS
import 'features/vehicles/providers/vehiculo_provider.dart';
import 'features/sync_dashboard/providers/sync_dashboard_provider.dart';
import 'features/vehicles/services/vehiculo_manager.dart';
import 'features/vehicles/services/vehiculo_repository.dart';
import 'features/vehicles/services/volvo_api_service.dart';

// Pantalla inicial
import 'features/auth/screens/login_screen.dart';

// Clave global
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ================= ERRORES =================
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("🚨 [ERROR GLOBAL ASÍNCRONO]: $error");
    return true;
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint("🚨 [ERROR GLOBAL FLUTTER]: ${details.exception}");
  };

  // ================= FIREBASE =================
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

  runApp(
    MultiProvider(
      providers: [
        // 🔹 API
        Provider(create: (_) => VolvoApiService()),

        // 🔹 REPO
        ProxyProvider<VolvoApiService, VehiculoRepository>(
          update: (_, api, __) => VehiculoRepository(api: api),
        ),

        // 🔹 MANAGER
        ProxyProvider2<VehiculoRepository, VolvoApiService, VehiculoManager>(
          update: (_, repo, api, __) => VehiculoManager(repo, api),
        ),

        // 🔹 PROVIDER UI
        ChangeNotifierProxyProvider2<
            VehiculoManager,
            VehiculoRepository,
            VehiculoProvider>(
          create: (context) => VehiculoProvider(
            manager: context.read<VehiculoManager>(),
            repository: context.read<VehiculoRepository>(),
          ),
          update: (_, manager, repo, provider) {
            provider!.manager = manager;
            provider.repository = repo;
            return provider;
          },
        ),

        // 🔥 DASHBOARD OBSERVABILIDAD
        ChangeNotifierProvider(
          create: (_) => SyncDashboardProvider(),
        ),
      ],
      child: const LogisticaApp(),
    ),
  );
}

// ================= APP =================

class LogisticaApp extends StatefulWidget {
  const LogisticaApp({super.key});

  @override
  State<LogisticaApp> createState() => _LogisticaAppState();
}

class _LogisticaAppState extends State<LogisticaApp> {
  AutoSyncService? _autoSync;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<VehiculoProvider>();
      // ✅ FIX: Inyectamos el dashboard para que reciba los eventos del autosync.
      final dashboard = context.read<SyncDashboardProvider>();

      // 🔥 init data
      provider.init();

      // 🔥 autosync
      _autoSync = AutoSyncService(provider, dashboard: dashboard);
      _autoSync!.start();
    });

    NotificationService.selectNotificationStream.stream
        .listen((String? payload) {
      if (payload == null) return;

      final nav = navigatorKey.currentState;
      if (nav == null) return;

      if (payload == 'vencimiento') {
        nav.pushNamed(AppRoutes.misVencimientos);
      } else if (payload == 'admin_revision') {
        nav.pushNamed(AppRoutes.adminRevisiones);
      }
    });
  }

  @override
  void dispose() {
    _autoSync?.stop();
    NotificationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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

      initialRoute:
          PrefsService.isLoggedIn ? AppRoutes.home : AppRoutes.login,

      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
      },

      onGenerateRoute: AppRouter.generateRoute,
      onUnknownRoute: AppRouter.unknownRoute,
    );
  }
}
