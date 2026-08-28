import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app/bootstrap.dart';
import 'app/root_switcher.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
import 'l10n/localizations_fallback.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'services/chat_service.dart';
import 'theme/exodo_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P2 auditoría: Inter (400/500/600/700) está empaquetada en assets/fonts/ y
  // declarada en pubspec.yaml → google_fonts la carga del AssetManifest local,
  // cero dependencias de red en el arranque en frío. allowRuntimeFetching se
  // conserva solo como red de seguridad ante una variante futura no empaquetada.
  GoogleFonts.config.allowRuntimeFetching = true;

  // 1. CAPA SÍNCRONA (0–15 ms, sin red)
  // Lectura síncrona de SharedPreferences antes del primer frame en el frame 0.
  // NO toca red ni bloquea la interfaz.
  final bootstrap = await Bootstrap.readSync();
  // PERF (arranque): la validación de red del backend guardado (GET /health,
  // hasta 3s de timeout) NO debe bloquear el primer frame. Corre en background;
  // si el usuario envía un mensaje antes de que termine, sendMessageStream ya
  // tiene su propia sonda paralela (600 ms) para elegir el backend vivo.
  // ignore: unawaited_futures
  ChatService.loadSavedWorkingUrl();

  // 2. CAPA ASÍNCRONA (fire-and-forget)
  // Supabase se inicializa en background en paralelo sin bloquear el arranque.
  final initFuture = SupabaseService.initialize();

  // Global Error Boundary Fallback: prevent red debug error boxes
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[ErrorWidget.builder] CAUGHT WIDGET CRASH: ${details.exception}\n${details.stack}');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Content rendering error',
        style: TextStyle(
          fontFamily: 'AnthropicSans',
          color: Color(0xFF8E8E93),
          fontSize: 12,
        ),
      ),
    );
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final state = AppState(bootstrap: bootstrap);
            // Cuando la inicialización de Supabase culmine en background,
            // conectamos los listeners de sincronización en tiempo real y perfil.
            // C11: si initialize() falla (sin red al arrancar), no debe quedar
            // una promesa rechazada sin manejar ni bloquear el arranque cacheado.
            initFuture
                .then((_) {
              state.initAfterSupabase();
            })
                .catchError((Object e) {
              debugPrint('[main] Supabase.initialize falló al arranque: $e');
            });
            return state;
          },
        ),
      ],
      child: AppI18nProvider(
        child: ExodoApp(
          initialHasSession: bootstrap.hasAuthToken,
        ),
      ),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  final bool initialHasSession;

  const ExodoApp({
    super.key,
    this.initialHasSession = false,
  });

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
      // Delegates con fallback ht→fr: flutter_localizations no soporta
      // Kreyòl (`ht`) y sin este wrapper cualquier widget que pida
      // MaterialLocalizations tumba el build con pantalla gris.
      localizationsDelegates: kExodoLocalizationsDelegates,
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
      home: RootSwitcher(
        initialHasSession: initialHasSession,
      ),
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => RootSwitcher(
          initialHasSession: initialHasSession,
        ),
      ),
    );
  }
}

Locale? _resolveLocale(String? appLocale) {
  if (appLocale == null) return null;
  if (!kAppLocales.any((l) => l.code == appLocale)) return null;
  final parts = appLocale.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0], '');
}
