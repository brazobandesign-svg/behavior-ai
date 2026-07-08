import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'theme/exodo_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // [Sprint 0] Permitir descarga HTTP de Google Fonts mientras no están bundled.
  GoogleFonts.config.allowRuntimeFetching = true;

  // No bloqueamos runApp: iniciamos la inicialización asíncrona pero abrimos
  // la UI al milisegundo 0 para que el usuario no vea una pantalla congelada.
  final initFuture = SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState())],
      child: AppI18nProvider(child: ExodoApp(initFuture: initFuture)),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  final Future<void> initFuture;
  const ExodoApp({super.key, required this.initFuture});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final userLocale = context.currentLocaleCode; // del AppI18nProvider

    return MaterialApp(
      title: AppI18n.of(context).t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: ExodoTheme.lightTheme,
      darkTheme: ExodoTheme.darkTheme,
      themeMode: (state.isDarkMode || state.isIncognito)
          ? ThemeMode.dark
          : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: kAppLocales
          .map((l) {
            final parts = l.code.split('_');
            return parts.length > 1
                ? Locale(parts[0], parts[1])
                : Locale(parts[0], '');
          })
          .toList(growable: false),
      locale: _resolveLocale(userLocale),
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (deviceLocale != null) {
          for (final supported in supportedLocales) {
            if (supported.languageCode == deviceLocale.languageCode &&
                (supported.countryCode == deviceLocale.countryCode ||
                    supported.countryCode == null ||
                    supported.countryCode!.isEmpty)) {
              return supported;
            }
          }
          for (final supported in supportedLocales) {
            if (supported.languageCode == deviceLocale.languageCode) {
              return supported;
            }
          }
        }
        return const Locale('es', '');
      },
      home: _RootSwitcher(initFuture: initFuture),
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => _RootSwitcher(initFuture: initFuture)),
    );
  }
}

Locale? _resolveLocale(String? appLocale) {
  if (appLocale == null) return null;
  if (!kAppLocales.any((l) => l.code == appLocale)) return null;
  final parts = appLocale.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0], '');
}

class _RootSwitcher extends StatefulWidget {
  final Future<void> initFuture;
  const _RootSwitcher({super.key, required this.initFuture});

  @override
  State<_RootSwitcher> createState() => _RootSwitcherState();
}

class _RootSwitcherState extends State<_RootSwitcher> {
  // [Punto 1 Fix real] Ya no bloqueamos el primer frame con un while(true)
  // esperando a Supabase. Leemos SharedPreferences directo (0-5ms, sin red)
  // para saber si HABÍA sesión guardada, y pintamos la pantalla correcta
  // de inmediato. Supabase.initialize() sigue corriendo en background y,
  // si la sesión resultó inválida/expirada, AppState reacciona al
  // authStateChange y navega a AuthScreen sin que el usuario note el salto.
  bool _hasCachedSession = false;
  bool _checkedCache = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _checkCachedSessionFast();
    // Supabase sigue inicializando en paralelo, no lo esperamos.
    widget.initFuture.then((_) {
      if (!mounted) return;
      context.read<AppState>().initAfterSupabase();
      // [Fix D] La variable de caché solo sirve para el primer frame.
      // A partir de aquí, cualquier cambio REAL de sesión (login,
      // logout, expiración) debe sincronizarla, o el build() sigue
      // devolviendo la pantalla vieja aunque AppState ya se haya
      // actualizado correctamente por dentro.
      _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final hasSession = data.session != null;
        if (hasSession != _hasCachedSession) {
          setState(() => _hasCachedSession = hasSession);
        }
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _checkCachedSessionFast() async {
    // Supabase persiste la sesión bajo esta clave en SharedPreferences.
    // Leerla es I/O local (sin red) y toma unos pocos milisegundos.
    final prefs = await SharedPreferences.getInstance();
    final hasToken = prefs.getKeys().any(
      (k) => k.startsWith('sb-') && k.contains('auth-token'),
    );
    if (!mounted) return;
    setState(() {
      _hasCachedSession = hasToken;
      _checkedCache = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Dependencia de AppState para rediseñar al iniciar o cerrar sesión.
    context.watch<AppState>();
    // Dependencia de _I18nScope: fuerza rebuild en cambio de idioma sin perder estado.
    context.currentLocaleCode;

    if (!_checkedCache) {
      return Scaffold(
        backgroundColor: ExodoColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/Logo_behavior.png',
                width: 64,
                height: 64,
              ),
              const SizedBox(height: 16),
              Image.asset(
                'assets/images/exodo_text.png',
                width: 110,
                color: ExodoColors.textPrimary,
              ),
            ],
          ),
        ),
      );
    }

    // Pintamos ChatScreen/AuthScreen de inmediato según lo que había en
    // caché. Si Supabase determina en background que la sesión ya no es
    // válida, el listener de authStateChange en AppState debe forzar
    // la navegación a AuthScreen (verificar que ese listener exista).
    return _hasCachedSession ? const ChatScreen() : const AuthScreen();
  }
}
