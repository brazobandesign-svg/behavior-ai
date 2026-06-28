import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'theme/exodo_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const AppI18nProvider(child: ExodoApp()),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  const ExodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final userLocale = context.currentLocaleCode; // del AppI18nProvider

    return MaterialApp(
      // [v1.2] KEY DINÁMICO POR LOCALE: garantiza rebuild completo de
      // TODO el árbol de widgets (incluidos widgets `const` y stateles
      // que cacheaban traducciones) cuando el usuario cambia de idioma.
      // Es el patrón estándar que usan Claude, Grok y Gemini para
      // asegurar que ningún string traducido quede stale.
      key: ValueKey('exodo-app-${userLocale ?? "sys"}'),
      title: AppI18n.of(context).t('app.title'),
      debugShowCheckedModeBanner: false,
      // Sin flash: ambos temas preconstruidos + themeMode reactivo.
      theme: ExodoTheme.lightTheme,
      darkTheme: ExodoTheme.darkTheme,
      themeMode: (state.isDarkMode || state.isIncognito) ? ThemeMode.dark : ThemeMode.light,
      // Transición instantánea entre temas (sin animación) para evitar el flash blanco/negro.
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      supportedLocales:
          kAppLocales.map((l) => Locale(l.code, '')).toList(growable: false),
      locale: _resolveLocale(userLocale), // null → cae a localeResolutionCallback
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (deviceLocale != null) {
          for (final supported in supportedLocales) {
            if (supported.languageCode == deviceLocale.languageCode) {
              return supported;
            }
          }
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

/// Resuelve el locale de la app para `MaterialApp.locale`.
/// - Si el usuario eligió uno en el picker (vía AppI18nProvider) Y está en
///   la lista de locales soportados → devuelve ese Locale.
/// - En cualquier otro caso (sin override, o override inválido) → null,
///   para que MaterialApp.useInheritedMediaQuery + localeResolutionCallback
///   caigan al locale del sistema (con fallback a 'es').
Locale? _resolveLocale(String? appLocale) {
  if (appLocale == null) return null;
  if (!kAppLocales.any((l) => l.code == appLocale)) return null;
  return Locale(appLocale, '');
}

class _RootSwitcher extends StatefulWidget {
  const _RootSwitcher();

  @override
  State<_RootSwitcher> createState() => _RootSwitcherState();
}

class _RootSwitcherState extends State<_RootSwitcher> {
  late final StreamSubscription<AuthState> _authSub;
  static bool _hasShownSplash = false;
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = !_hasShownSplash;
    _hasShownSplash = true;
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
    
    // 1. Si está activo el splash screen -> Mostrar splash
    if (_showSplash) {
      return SplashScreen(
        onFinished: () {
          if (mounted) {
            setState(() {
              _showSplash = false;
            });
          }
        },
      );
    }

    final user = SupabaseService.currentUser;

    // 2. Si no ha iniciado sesión -> Pantalla de Autenticación
    if (user == null) {
      return const AuthScreen();
    }

    // 3. Todo listo -> Chat Principal directo (las preguntas de enfoque saldrán como modal dentro del chat)
    return const ChatScreen();
  }
}

