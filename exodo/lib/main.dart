import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app/bootstrap.dart';
import 'app/root_switcher.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'services/chat_service.dart';
import 'theme/exodo_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Permitir descarga HTTP de Google Fonts mientras no están bundled.
  GoogleFonts.config.allowRuntimeFetching = true;

  // 1. CAPA SÍNCRONA (0–15 ms, sin red)
  // Lectura síncrona de SharedPreferences antes del primer frame en el frame 0.
  // NO toca red ni bloquea la interfaz.
  final bootstrap = await Bootstrap.readSync();
  await ChatService.loadSavedWorkingUrl();

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
            initFuture.then((_) {
              state.initAfterSupabase();
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
