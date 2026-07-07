import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
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
  StreamSubscription<AuthState>? _authSub;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    widget.initFuture.then((_) {
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
      try {
        _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
          if (mounted) setState(() {});
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dependencia de _I18nScope: fuerza rebuild en cambio de idioma sin perder estado.
    context.currentLocaleCode;

    if (!_isInitialized) {
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

    final session = SupabaseService.client.auth.currentSession;
    return session != null ? const ChatScreen() : const AuthScreen();
  }
}
