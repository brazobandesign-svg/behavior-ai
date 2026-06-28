import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'theme/exodo_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const ExodoApp(),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  const ExodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return MaterialApp(
      title: 'Éxodo by Behavior',
      debugShowCheckedModeBanner: false,
      // Sin flash: ambos temas preconstruidos + themeMode reactivo.
      theme: ExodoTheme.lightTheme,
      darkTheme: ExodoTheme.darkTheme,
      themeMode: (state.isDarkMode || state.isIncognito) ? ThemeMode.dark : ThemeMode.light,
      // Transición instantánea entre temas (sin animación) para evitar el flash blanco/negro.
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      supportedLocales: const [
        Locale('en', ''),
        Locale('es', ''),
      ],
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (deviceLocale != null && deviceLocale.languageCode == 'en') {
          return const Locale('en', '');
        }
        return const Locale('es', '');
      },
      home: const _RootSwitcher(),
      // Necesario para que supabase_flutter maneje el deep link OAuth (?code=...)
      // sin que el Navigator crashee al no encontrar la ruta
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const _RootSwitcher(),
      ),
    );
  }
}

class _RootSwitcher extends StatefulWidget {
  const _RootSwitcher();

  @override
  State<_RootSwitcher> createState() => _RootSwitcherState();
}

class _RootSwitcherState extends State<_RootSwitcher> {
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    // Escuchar cambios de autenticación para forzar rebuild del widget tree
    // (AppState._init() ya maneja loadUserData/clear internamente)
    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      debugPrint('[RootSwitcher] Auth event: ${data.event}');
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final user = SupabaseService.currentUser;

    // 1. Si no ha iniciado sesión -> Pantalla de Autenticación
    if (user == null) {
      return const AuthScreen();
    }

    // 2. Todo listo -> Chat Principal directo (las preguntas de enfoque saldrán como modal dentro del chat)
    return const ChatScreen();
  }
}
